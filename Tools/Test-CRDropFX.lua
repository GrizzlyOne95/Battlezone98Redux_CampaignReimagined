-- Scripts/CRDropFX.lua against a stub EXU particle API: nozzle placement per hull layout, the throttle through
-- descent, landing, ramp fold and climb, the seamless c -> o -> x hull swap, cleanup, and the no-EXU path.
-- Engine rendering is not covered (Ogre skips a malformed template silently: smoke it in game). Run from the
-- repository root:
--   lua5.1 Tools/Test-CRDropFX.lua
assert(_VERSION == "Lua 5.1")
package.path = "Scripts/?.lua;" .. package.path
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local V = function(x, y, z) return { x = x, y = y, z = z } end
_G.SetVector = V
local GROUND = 20
_G.GetTerrainHeightAndNormal = function() return GROUND, V(0, 1, 0) end

local now, objects, nextId, systems, lights, created, logs
local function hull(odf, x, y, z, yaw)
    nextId = nextId + 1
    objects[nextId] = { odf = odf, x = x, y = y, z = z, yaw = yaw or 0 }
    return nextId
end
_G.IsValid = function(h) return objects[h] ~= nil end
_G.GetOdf = function(h) return objects[h].odf end
_G.GetPosition = function(h) local o = objects[h]; return V(o.x, o.y, o.z) end
_G.GetTransform = function(h)
    -- yaw about +y: front = (sin, 0, cos), right = (cos, 0, -sin)
    local o = objects[h]
    local s, c = math.sin(o.yaw), math.cos(o.yaw)
    return { right_x = c, right_y = 0, right_z = -s, up_x = 0, up_y = 1, up_z = 0, front_x = s, front_y = 0,
        front_z = c, posit_x = o.x, posit_y = o.y, posit_z = o.z }
end
_G.AllObjects = function()
    local list = {}
    for h in pairs(objects) do list[#list + 1] = h end
    table.sort(list)
    local i = 0
    return function() i = i + 1; return list[i] end
end

local stub = {
    CreateParticleSystem = function(name, template, at)
        systems[name] = { template = template, pos = at, rate = nil }
        created = created + 1
        return true
    end,
    DestroyParticleSystem = function(name) systems[name] = nil; return true end,
    SetParticleSystemPosition = function(name, at) systems[name].pos = at; return true end,
    SetParticleEmitterEmissionRate = function(name, i, rate) check(i == 0, "emitter 0"); systems[name].rate = rate; return true end,
    SetParticleSystemKeepLocalSpace = function() return true end,
    SetParticleSystemNonVisibleUpdateTimeout = function() return true end,
    CreatePointLight = function(name, at) lights[name] = { pos = at, power = 1 }; return true end,
    SetPointLightPosition = function(name, at) lights[name].pos = at; return true end,
    SetPointLightPowerScale = function(name, p) lights[name].power = p; return true end,
    DestroyPointLight = function(name) lights[name] = nil; return true end,
}

local function fresh(options)
    now, objects, nextId, systems, lights, created, logs = 0, {}, 0, {}, {}, 0, {}
    package.loaded.CRDropFX = nil
    local FX = require("CRDropFX")
    local o = { exu = stub, templates = function() return true end, time = function() return now end,
        log = function(line) logs[#logs + 1] = line end }
    for k, v in pairs(options or {}) do o[k] = v end
    FX.Configure(o)
    return FX
end
local function tick(FX, dt, n, each)
    for _ = 1, n or 1 do
        now = now + dt
        if each then each() end
        FX.Update()
    end
end
local function count(kind)
    local n = 0
    for name in pairs(systems) do if name:find("/" .. kind .. "%d*$") then n = n + 1 end end
    return n
end
local function sys(kind)
    for name, s in pairs(systems) do if name:find("/" .. kind .. "$") then return s, name end end
end

-- 1. Pure helpers.
do
    local FX = fresh()
    local b, s = FX.Classify("avdropc"); check(b == "avdrop" and s == "c", "avdropc")
    b, s = FX.Classify("BVDROPO"); check(b == "bvdrop" and s == "o", "case-insensitive bvdropo")
    b, s = FX.Classify("svdropx"); check(b == "svdrop" and s == "x", "svdropx")
    b, s = FX.Classify("cvdropc"); check(b == "cvdrop" and s == "c", "cvdropc")
    check(FX.Classify("avdrop") == nil and FX.Classify("avrecy") == nil and FX.Classify("apcamr") == nil
        and FX.Classify(nil) == nil and FX.Classify("zzdropc") == nil, "nothing else is a dropship hull")
    check(FX.LAYOUTS.bvdrop == FX.LAYOUTS.avdrop, "bvdrop shares avdrop's nozzles")
    check(#FX.LAYOUTS.avdrop.nozzles == 6 and #FX.LAYOUTS.svdrop.nozzles == 8 and #FX.LAYOUTS.cvdrop.nozzles == 4,
        "nozzle counts: 6 lift bells, 8 hover jets, 4 leg rockets")
    for name, l in pairs(FX.LAYOUTS) do
        for i = 1, #l.nozzles, 2 do
            local a, m = l.nozzles[i], l.nozzles[i + 1]
            check(a[1] == -m[1] and a[2] == m[2] and a[3] == m[3], name .. " nozzles mirror in x")
        end
    end
    check(FX.Target("c", 100, -5, 0) == 1 and FX.Target("c", 0.5, -1, 9) == 1, "a flying or settling hull runs full")
    check(FX.Target("o", 100, 0, 0) == 0, "a landed hull is off")
    check(FX.Target("x", 0, 0, 0) == 0 and near(FX.Target("x", 0, 0, FX.SPOOL_UP_T / 2), FX.IDLE / 2)
        and FX.Target("x", 0, 0, 99) == FX.IDLE, "a closing hull spools to idle on the ground")
    check(FX.Target("x", 0.2, 1, 0) == 1 and FX.Target("x", 10, 0, 0) == 1, "a climbing hull runs full")
    check(FX.Target("x", 0.2, -1, 99) == FX.IDLE, "a closing hull does not run full for a settling bump")
    check(near(FX.Step(0, 1, FX.RISE_T / 2), 0.5) and FX.Step(0, 1, 9) == 1, "throttle rises fast")
    check(near(FX.Step(1, 0, FX.FALL_T / 2), 0.5) and FX.Step(1, 0, 9) == 0, "throttle falls slowly")
end

-- 2. Idle module does nothing; without the API it says so once and stays inert.
do
    local FX = fresh()
    hull("avdropc", 0, 300, 0)
    tick(FX, 0.1, 20)
    check(created == 0 and not FX.Busy(), "no Watch: no scan, no systems")
    local FX2 = fresh({ exu = { CreateParticleSystem = stub.CreateParticleSystem } })
    hull("avdropc", 0, 300, 0)
    check(FX2.Watch() == false and FX2.Watch() == false and #logs == 1 and logs[1]:find("unavailable"),
        "an EXU without the particle setters: one log line, no Watch")
    tick(FX2, 0.1, 20)
    check(created == 0, "inert without the API")
    local FX3 = fresh({ templates = function() return false, "payload missing" end })
    hull("avdropc", 0, 300, 0)
    check(FX3.Watch() == false and logs[1]:find("payload missing"), "missing templates: logged, inert")
    local FX4 = fresh({ exu = false })
    _G.exu = nil
    check(FX4.Watch() == false, "no EXU at all")
end

-- 3. avdrop: descent at full thrust, nozzles on the hull, the c -> o -> x swap, climb and cleanup.
do
    local FX = fresh()
    local yaw = math.pi / 2   -- bow along +x: right is -z
    local h = hull("avdropc", 100, 320, 200, yaw)
    check(FX.Watch() == true, "Watch arms")
    tick(FX, 1 / 30)
    check(FX.Busy() and count("Jet") == 6 and count("Core") == 6 and count("Wash") == 1, "6 jets, 6 cores, 1 wash")
    local light = next(lights)
    check(light ~= nil, "one engine light")
    local d = FX.Describe().tracks[1]
    check(#FX.Describe().tracks == 1 and d.base == "avdrop" and d.suffix == "c" and d.power == 1,
        "first sight of a flying hull: full thrust at once")
    -- nozzle 1 = (right 28.8, up 9.7, front 6.5); with this yaw right = (0,0,-1), front = (1,0,0)
    local jet1 = systems["CRDrop/1/Jet1"]
    check(jet1 and jet1.template == FX.JET and near(jet1.pos.x, 100 + 6.5, 1e-6) and near(jet1.pos.y, 320 + 9.7, 1e-6)
        and near(jet1.pos.z, 200 - 28.8, 1e-6), "jet 1 sits on the starboard forward bell")
    check(systems["CRDrop/1/Core1"].pos.x == jet1.pos.x and systems["CRDrop/1/Core1"].template == FX.CORE,
        "the hot core shares the jet's nozzle")
    check(near(jet1.rate, FX.JET_RATE) and near(systems["CRDrop/1/Core1"].rate, FX.CORE_RATE), "full rates")
    local wash = sys("Wash")
    check(wash.rate == 0 and near(wash.pos.y, GROUND + 0.5), "no wash 300 m up; it sits on the ground")
    -- the hull moves: the jets follow it
    objects[h].x = 150
    tick(FX, 1 / 30)
    check(near(systems["CRDrop/1/Jet1"].pos.x, 150 + 6.5, 1e-6), "the jets follow the hull")
    -- descend to the ground: the wash builds as the bells near it
    local washSeen = 0
    tick(FX, 1 / 30, 30 * 25, function()   -- 300 m at 12 m/s: the swap comes on the touchdown frame
        objects[h].y = math.max(GROUND, objects[h].y - 12 / 30)
        washSeen = math.max(washSeen, sys("Wash").rate)
    end)
    check(washSeen > FX.WASH_RATE * 0.5, "the wash builds near the ground")
    -- touchdown: the leader swaps the flying hull for the landed one in the same frame
    local before = created
    objects[h] = nil
    local o = hull("avdropo", 150, GROUND, 200, yaw)
    tick(FX, 1 / 30)
    tick(FX, 1 / 30)
    check(created == before and #FX.Describe().tracks == 1 and FX.Describe().tracks[1].suffix == "o",
        "the landed hull takes over the flying hull's systems (no blink, no new systems)")
    check(FX.Describe().tracks[1].power > 0.9, "the throttle carries over the swap")
    tick(FX, 1 / 30, 30 * 3)
    check(FX.Describe().tracks[1].power == 0 and sys("Wash").rate == 0 and systems["CRDrop/1/Jet1"].rate == 0
        and lights[light].power == 0, "landed: spooled down, no wash, light out")
    tick(FX, 1 / 30, 30 * 20)
    check(FX.Busy() and #FX.Describe().tracks == 1, "a landed ship keeps its (idle) systems while it waits")
    -- the ramps fold: closing hull, spools to idle
    objects[o] = nil
    local x = hull("avdropx", 150, GROUND, 200, yaw)
    tick(FX, 1 / 30, 30 * 3)
    check(created == before and near(FX.Describe().tracks[1].power, FX.IDLE, 0.02), "ramps folding: idle thrust")
    -- lift-off and climb
    tick(FX, 1 / 30, 30 * 4, function() objects[x].y = objects[x].y + 6 / 30 end)
    check(FX.Describe().tracks[1].power == 1 and near(systems["CRDrop/1/Jet1"].rate, FX.JET_RATE), "climbing: full thrust")
    -- removed far overhead: the systems fade out, then go
    objects[x] = nil
    tick(FX, 1 / 30, math.floor(30 * (FX.HANDOVER + 0.2)))
    check(FX.Describe().tracks[1].fading and systems["CRDrop/1/Jet1"].rate == 0, "a lost hull stops emitting")
    tick(FX, 1 / 30, math.floor(30 * (FX.FADE_T + 0.2)))
    check(not FX.Busy() and next(systems) == nil and next(lights) == nil, "then every system and the light are destroyed")
end

-- 4. Two ships, svdrop and cvdrop layouts; a far new hull never steals a lost one's systems.
do
    local FX = fresh()
    local a = hull("svdropc", 0, 200, 0)
    local b = hull("cvdropc", 500, 200, 0)
    FX.Watch()
    tick(FX, 1 / 30)
    check(count("Jet") == 8 + 4 and #FX.Describe().tracks == 2, "svdrop 8 jets + cvdrop 4 jets")
    local foundSv, foundCv
    for name, s in pairs(systems) do
        if s.template == FX.JET and near(s.pos.x, 18.5) and near(s.pos.y, 203) and near(s.pos.z, 41.5) then foundSv = true end
        if s.template == FX.JET and near(s.pos.x, 500 - 30) and near(s.pos.y, 200.4) and near(s.pos.z, -24) then foundCv = true end
    end
    check(foundSv and foundCv, "svdrop fang jet and cvdrop aft leg rocket at their nozzles")
    local before = created
    objects[a] = nil
    hull("svdropo", 300, 200, 0)   -- 300 m away: a different ship, not the swap
    tick(FX, 1 / 30, 2)
    check(created > before and #FX.Describe().tracks == 3, "a far hull gets its own systems")
    FX.Reset()
    check(next(systems) == nil and next(lights) == nil and not FX.Busy(), "Reset destroys everything")
    tick(FX, 1 / 30, 30)
    check(created == before + 17, "after Reset nothing is scanned until the next Watch")
    _ = b
end

-- 5. The watch window: a Watch with no hull in sight gives up; a hull built later inside the window is found.
do
    local FX = fresh()
    FX.Watch()
    tick(FX, 1 / 30, 30 * 5)
    hull("bvdropc", 0, 300, 0)
    tick(FX, 1 / 30, 30)
    check(count("Jet") == 6, "a hull built after the Watch is found")
    FX.Reset()
    objects = {}
    FX.Watch()
    tick(FX, 1, FX.WATCH_T + 2)
    check(not FX.Describe().watching, "an empty watch expires")
end

-- 6. A failed create cleans up after itself.
do
    local FX = fresh()
    local n = 0
    stub.CreateParticleSystem, stub.real = function(name, template, at)
        n = n + 1
        if n == 5 then return false end
        return stub.real(name, template, at)
    end, stub.CreateParticleSystem
    hull("avdropc", 0, 300, 0)
    FX.Watch()
    tick(FX, 1 / 30)
    check(next(systems) == nil and #FX.Describe().tracks == 0, "a half-built hull leaves no systems behind")
    local tries = n
    tick(FX, 1, 3)
    check(n == tries, "a hull that failed is not retried every scan")
    stub.CreateParticleSystem = stub.real
end

print(string.format("CRDropFX: %d checks passed", checks))
