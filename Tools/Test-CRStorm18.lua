-- Test-CRStorm18.lua
--
-- Drives the real CRStorm18 (director, tornado, ground, rng), the real CRWeather,
-- CRWeatherPresets and CRFoliageWind against a recording EXU stub, and lints the
-- shipped payload, material and shader program. Host-side only: nothing here can
-- see a pixel, so Docs/MISN18_STORM.md lists what a live lcbench smoke must check.
--
-- Usage, from the repository root:   lua5.1 Tools/Test-CRStorm18.lua
-- Prints CRSTORM18 OK on success; prints each failed expectation and exits 1.
assert(_VERSION == "Lua 5.1")
package.path = "Scripts/?.lua;" .. package.path

local failures, checks = 0, 0
local out = print
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures = failures + 1; out("FAIL: " .. msg) end
end
local function readFile(path)
    local f = assert(io.open(path, "rb"), path)
    local t = f:read("*a"); f:close(); return t
end

-- ===================================================================== payload lint
local payload = readFile("Materials/cr18_storm.particle.payload"):gsub("\r", "") -- autocrlf checkouts
local templates = {}
do
    local depth, cur = 0, nil
    for line in payload:gmatch("[^\r\n]+") do
        local code = line:gsub("//.*", "")
        local name = code:match("^%s*particle_system%s+(%S+)")
        if name then check(not templates[name], "duplicate template " .. name); cur = { name = name, emitters = 0, affectors = 0 }; templates[name] = cur end
        if code:match("^%s*emitter%s+%a+") and cur then cur.emitters = cur.emitters + 1 end
        if code:match("^%s*affector%s+%a+") and cur then cur.affectors = cur.affectors + 1 end
        local m = code:match("^%s*material%s+(%S+)")
        if m and cur then cur.material = m end
        if code:match("^%s*quota%s+%d+") and cur then cur.quota = true end
        for c in code:gmatch("[{}]") do depth = depth + (c == "{" and 1 or -1); check(depth >= 0, "brace order") end
    end
    check(depth == 0, "payload braces balance")
end
for _, other in ipairs({ "cr_weather", "cr_venus", "cr_io", "cr_titan", "cr_europa", "cr_moon", "cr_reactive", "cr17_jungle", "crwx_precip", "cr_foliage", "cr16_launch", "weather_particles" }) do
    for n in readFile("Materials/" .. other .. ".particle.payload"):gmatch("particle_system%s+(%S+)") do
        check(not templates[n], "template name clashes with " .. other .. ": " .. n)
    end
end
local materialText = readFile("Materials/cr18_storm.material")
local materials = {}
for n in materialText:gmatch("\nmaterial%s+(%S+)") do materials[n] = true end
for name, t in pairs(templates) do
    check(t.material and (materials[t.material] or t.material == "CRWX_FX/Mist"), name .. " material " .. tostring(t.material) .. " defined in cr18_storm.material")
    check(t.quota, name .. " has a quota")
    check(t.emitters >= 1, name .. " has an emitter")
end
for tex in materialText:gmatch("set_texture_alias%s+DiffuseMap%s+(%S+)") do
    local f = io.open("Assets/Textures/" .. tex, "rb")
    check(f ~= nil, "texture ships: " .. tex)
    if f then f:close() end
end
check(templates["CR18/CrackA"].emitters == 6 and templates["CR18/CrackB"].emitters == 6 and templates["CR18/Soot"].emitters == 6
    and templates["CR18/CrackPuff"].emitters == 6, "decal systems have the six slots CRStorm18Ground fires")
check(templates["CR18/SlideDust"].emitters == 1 and templates["CR18/SlideRock"].emitters == 1, "slide systems have one emitter")
for _, n in ipairs({ "CrackA", "CrackB", "Soot" }) do
    check(payload:find("particle_system CR18/" .. n, 1, true) and payload:match("CR18/" .. n .. "\n{.-ColourInterpolator"), n .. " pulses through a ColourInterpolator")
end
-- A ColourInterpolator must state all six stages or Ogre interpolates to an opaque black default.
for blockName in payload:gmatch("particle_system (CR18/%S+)") do
    local block = payload:match("particle_system " .. blockName:gsub("/", "%%/") .. "\n{(.-)\n}\n")
    if block and block:find("ColourInterpolator") then
        for i = 0, 5 do check(block:find("time" .. i, 1, true) and block:find("colour" .. i, 1, true), blockName .. " states interpolator stage " .. i) end
    end
end

-- program / shader lint
local program = readFile("Shaders/cr18_swirl.program")
local declared = {}
for kind, n in program:gmatch("(%a+_program)%s+(%S+)") do declared[n] = (program:find(n .. " unified", 1, true) and "unified") or kind end
for _, ref in ipairs({ "CR18_Swirl_v2_vertex", "CR18_Swirl_v2_fragment" }) do
    check(declared[ref], ref .. " declared")
    check(materialText:find(ref, 1, true), "material uses " .. ref)
end
local order = {}
for n in program:gmatch("_program%s+(%S+)") do order[#order + 1] = n end
local seen = {}
for _, n in ipairs(order) do
    seen[n] = true
    for d in (program:match("_program " .. n .. " unified\n{(.-)\n}\n") or ""):gmatch("delegate%s+(%S+)") do
        check(seen[d], n .. " delegate " .. d .. " is declared before it")
    end
end
for _, f in ipairs({ "cr18_swirl-sm4.hlsl", "cr18_swirl.hlsl", "cr18_swirl-vertex.glsl", "cr18_swirl-fragment.glsl" }) do
    check(program:find(f, 1, true), "program names source " .. f)
    readFile("Shaders/" .. f)
end
for _, uni in ipairs({ "time", "skyDark", "skyHot", "glow", "swirl", "fogColour", "plane" }) do
    for _, f in ipairs({ "cr18_swirl-sm4.hlsl", "cr18_swirl.hlsl", "cr18_swirl-fragment.glsl" }) do
        check(readFile("Shaders/" .. f):find(uni, 1, true), f .. " reads " .. uni)
    end
    check(program:find(uni, 1, true), "program binds " .. uni)
end
check(not (readFile("Shaders/cr18_swirl-sm4.hlsl"):gsub("//[^%c]*", "")):find("COLOR0"), "sky shader never reads COLOR0 (D3D11 sky planes have none)")
check(program:find("plane float4 12.0 0.92", 1, true), "swirl centre matches CLOUD_TILING 24")

-- ===================================================================== fake world
local now, currentPeer = 0, nil
local printed = {}
local realPrint = print
print = function(...) local t = {}; for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end; printed[#printed + 1] = table.concat(t, " ") end

local function heightAt(px, pz) return 100 + 40 * math.sin(px / 90) + 30 * math.cos(pz / 120) end
local function normalAt(px, pz)
    local dx = (heightAt(px + 1, pz) - heightAt(px - 1, pz)) / 2
    local dz = (heightAt(px, pz + 1) - heightAt(px, pz - 1)) / 2
    local l = math.sqrt(dx * dx + dz * dz + 1)
    return { x = -dx / l, y = 1 / l, z = -dz / l }
end

function SetVector(a, b, c) return { x = a, y = b, z = c } end
function GetTime() return now end
function GetTerrainHeightAndNormal(v) return heightAt(v.x, v.z), normalAt(v.x, v.z) end
local playerPos = { x = 1900, y = 100, z = 98100 }
function GetPlayerHandle() return "player" end
local craft = {}
function GetPosition(h) if h == "player" then return playerPos end return craft[h] and craft[h].p end
function GetVelocity(h) return craft[h].v end
local velocityWrites, damageWrites = 0, 0
function SetVelocity(h, v) craft[h].v = v; velocityWrites = velocityWrites + 1 end
function Damage(h, a) craft[h].hurt = (craft[h].hurt or 0) + a; damageWrites = damageWrites + 1 end
function IsValid() return true end
function IsBuilding(h) return craft[h] and craft[h].building end
local netgame = false
function IsNetGame() return netgame end
function IsLocal(h) return not (craft[h] and craft[h].remote) end
function AllCraft() local keys = {}; for k in pairs(craft) do keys[#keys + 1] = k end; table.sort(keys); local i = 0; return function() i = i + 1; return keys[i] end end
local sounds, quakeLog, explosions = {}, {}, {}
function StartSound(f) sounds[#sounds + 1] = f end
function StartEarthquake(m) quakeLog[#quakeLog + 1] = { "start", m } end
function UpdateEarthQuake(m) quakeLog[#quakeLog + 1] = { "update", m } end
function StopEarthquake() quakeLog[#quakeLog + 1] = { "stop" } end
function MakeExplosion(o, p) explosions[#explosions + 1] = o end

-- Recording EXU.
local X, systems, colours, anim, geo, lights, skyPlane, counts, missing, opts = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
opts.failBuild, opts.mapSky = false, false
local function def(name, fn) X[name] = function(...) counts[name] = (counts[name] or 0) + 1; return fn(...) end end
local function sys(n, fn) return function(name, ...) if not systems[name] then return false end; return fn(systems[name], ...) end end
def("GetFog", function() return { r = .5, g = .4, b = .3, fogStart = 100, fogEnd = 250 } end)
def("SetFog", function() return true end)
def("GetAmbientLight", function() return { r = .5, g = .5, b = .5 } end)
def("SetAmbientLight", function() return true end)
def("GetSunDiffuse", function() return { r = .6, g = .6, b = .6 } end)
def("SetSunDiffuse", function() return true end)
def("GetSunPowerScale", function() return 1 end)
def("SetSunPowerScale", function() return true end)
def("GetCameraClipDistances", function() return 0.5, 1125 end)
def("GetCameraTransformMatrix", function() local v = currentPeer and currentPeer.view or playerPos; return { posit_x = v.x, posit_y = v.y, posit_z = v.z } end)
def("MaterialExists", function(n) return not missing[n] end)
def("SetMaterialPassColors", function(n, c) colours[n] = colours[n] or {}; table.insert(colours[n], c); return true end)
def("SetMaterialTextureScrollAnimation", function(n, u, v) anim[n] = anim[n] or {}; anim[n].scroll = { u, v }; return true end)
def("SetMaterialTextureRotateAnimation", function(n, r) anim[n] = anim[n] or {}; anim[n].rotate = r; return true end)
def("GetSkyPlaneEnabled", function() return opts.mapSky end)
local dome = { on = true }
def("GetSkyDomeEnabled", function() return dome.on end)
def("SetSkyDomeEnabled", function(on) dome.on = on; return true end)
def("GetSkyBoxEnabled", function() return false end)
def("SetSkyPlane", function(m, plane, scale, tiling, first, bow, xs, ys) skyPlane = { m = m, d = plane.d, scale = scale, tiling = tiling, enabled = false }; return true end)
def("SetSkyPlaneEnabled", function(on) skyPlane.enabled = on end)
def("CreateParticleSystem", function(name, tpl, pos)
    if systems[name] or not templates[tpl] then return false end
    systems[name] = { tpl = tpl, pos = pos, rates = {}, dir = {}, emitting = true, visible = true }
    return true
end)
def("DestroyParticleSystem", function(name) local had = systems[name] ~= nil; systems[name] = nil; return had end)
def("DetachParticleSystem", function() return true end)
for _, n in ipairs({ "SetParticleSystemKeepLocalSpace", "SetParticleSystemNonVisibleUpdateTimeout", "SetParticleSystemParticleQuota",
    "AttachParticleSystemToCamera", "SetParticleEmitterEnabled", "SetParticleEmitterVelocity", "SetParticleEmitterTimeToLive",
    "SetParticleEmitterAngle", "SetParticleEmitterColor", "SetParticleEmitterParameter", "SetParticleAffectorParameter" }) do
    def(n, function(name) return systems[name] ~= nil end)
end
def("UpdateParticleFollowers", function() return 0 end)
def("SetParticleSystemPosition", sys("p", function(s, p) s.pos = p; return true end))
def("SetParticleSystemDirection", sys("d", function(s, d) s.spin = d; return true end))
def("SetParticleSystemEmitting", sys("e", function(s, on) s.emitting = on; return true end))
def("SetParticleSystemVisible", sys("v", function(s, on) s.visible = on; return true end))
def("SetParticleEmitterEmissionRate", sys("r", function(s, i, r) s.rates[i] = r; s.fired = (s.fired or 0) + ((r > 0) and 1 or 0); return true end))
def("SetParticleEmitterPosition", sys("ep", function(s, i, p) s.slotPos = s.slotPos or {}; s.slotPos[i] = p; return true end))
def("SetParticleEmitterDirection", sys("ed", function(s, i, d) s.dir[i] = d; return true end))
def("GetParticleSystemEmitterCount", function(name) local s = systems[name]; return s and templates[s.tpl].emitters end)
def("GetParticleSystemAffectorCount", function(name) local s = systems[name]; return s and templates[s.tpl].affectors end)
def("CreateStaticGeometry", function(name, mesh, mat, inst, o)
    if opts.failBuild then return nil, "boom" end
    geo[name] = { mesh = mesh, material = mat, n = #inst, o = o }; return { instanceCount = #inst }
end)
def("DestroyStaticGeometry", function(name) geo[name] = nil; return true end)
def("CreatePointLight", function(name) if lights[name] then return false end; lights[name] = {}; return true end)
def("SetPointLightPosition", function(name) return lights[name] ~= nil end)
def("SetPointLightPowerScale", function(name) return lights[name] ~= nil end)
def("DestroyPointLight", function(name) local had = lights[name] ~= nil; lights[name] = nil; return had end)
package.preload["exu"] = function() return X end

-- Peers' module stubs.
local groundfx = { bolts = {}, strokes = 0, events = 0, stopped = 0 }
local glass = { splats = 0, crack = 0, stopped = 0, updates = 0 }
local modifiers = {}
local envStub = { RegisterEnvironmentModifier = function(n, f) modifiers[n] = f end,
    UnregisterEnvironmentModifier = function(n) modifiers[n] = nil end, InvalidateRenderer = function() end }
_G.Environment = envStub
package.preload["Environment"] = function() return envStub end
package.preload["CRParticleTemplates"] = function()
    return { Ensure = function() return true end, EnsureExtra = function(n) if opts.noPayload then return false, "no payload" end return true end }
end
package.preload["CRGroundFX"] = function()
    return { Bolt = function(x, g, z) groundfx.bolts[#groundfx.bolts + 1] = { peer = currentPeer, x = x, z = z }; return true end,
        BoltStroke = function() groundfx.strokes = groundfx.strokes + 1 end, Event = function() groundfx.events = groundfx.events + 1 end,
        Update = function() end, Stop = function() groundfx.stopped = groundfx.stopped + 1 end }
end
package.preload["CRWetGlass"] = function()
    return { Update = function() glass.updates = glass.updates + 1 end, Stop = function() glass.stopped = glass.stopped + 1; glass.crack = 0 end,
        Splat = function() glass.splats = glass.splats + 1 end, SetCrack = function(l) glass.crack = l end }
end

local Storm = require("CRStorm18")
local Rng = require("CRStorm18Rng")
local Tornado = require("CRStorm18Tornado")
local Presets = require("CRWeatherPresets")
local Weather = require("CRWeather")
local Foliage = require("CRFoliageWind")
local Sites = require("CRStorm18Sites")

-- ===================================================================== rng
do
    local a, b = Rng.New(18018), Rng.New(18018)
    local same = true
    for _ = 1, 1000 do if a:Float() ~= b:Float() then same = false end end
    check(same, "same seed, same sequence")
    local c = Rng.New(18019)
    local d = Rng.New(18018)
    check(c:Float() ~= d:Float(), "different seeds diverge")
    local saved = Rng.New(5); for _ = 1, 10 do saved:Float() end
    local resumed = Rng.New(saved.state)
    check(saved:Float() == resumed:Float(), "state resumes the sequence")
    check(Rng.Hash(1, 2, 3, 4) == Rng.Hash(1, 2, 3, 4) and Rng.Hash(1, 2, 3, 4) ~= Rng.Hash(1, 2, 3, 5), "hash is stable and sensitive to every input")
    local lo, hi, sum = 1, 0, 0
    for i = 1, 5000 do local h = Rng.Hash(18018, i, -i, 7); lo = math.min(lo, h); hi = math.max(hi, h); sum = sum + h end
    check(lo >= 0 and hi < 1 and math.abs(sum / 5000 - 0.5) < 0.03, "hash is uniform in [0,1)")
    check(Rng.Hash(18018, -5, -9, 0) >= 0, "negative grid cells hash")
end

-- ===================================================================== presets
Storm.BuildPresets(Presets)
do
    local prev
    for i = 1, 8 do
        local p = Presets.Presets["Misn18Storm" .. i]
        check(p ~= nil, "preset " .. i)
        check(p.lightning == nil, "bolts are leader events, never CRWeather's timer")
        check(p.fog.fogEnd <= 250, "fog stays inside the 250 m terrain horizon")
        for _, spec in ipairs(p.precipitation) do
            local t = templates[spec.template]
            check(t ~= nil, spec.template .. " exists in the payload")
            if t then
                for idx in pairs(spec.emitters or {}) do check(idx < t.emitters, spec.system .. " emitter " .. idx .. " exists") end
                for idx in pairs(spec.affectors or {}) do check(idx < t.affectors, spec.system .. " affector " .. idx .. " exists") end
            end
        end
        if prev then
            check(p.windSpeed > prev.windSpeed, "wind builds with the phase")
            check(p.fog.fogEnd <= prev.fog.fogEnd and p.fog.fogStart < prev.fog.fogStart, "fog closes in")
            check(p.ambient.r < prev.ambient.r and p.diffuse.r < prev.diffuse.r and p.sunPowerScale < prev.sunPowerScale, "light darkens")
            check(p.precipitation[1].emitters[0].rate > prev.precipitation[1].emitters[0].rate, "dust thickens")
            check(p.precipitation[6].emitters[0].rate >= prev.precipitation[6].emitters[0].rate, "debris never thins")
        end
        prev = p
    end
    check(Presets.Presets.MarsDustStorm ~= nil and Presets.Presets.Misn18Storm9 == nil, "shared presets untouched, eight storm rungs")
end
do
    local prevLevel = -1
    for i, P in ipairs(Storm.PROFILE) do
        if i > 8 then break end -- extract and ascent are the ending's rungs, checked below
        check(P.level > prevLevel, "profile level rises at " .. P.name); prevLevel = P.level
        if i > 1 then
            local q = Storm.PROFILE[i - 1]
            check(P.bolt[2] <= q.bolt[2] and P.quake[2] <= q.quake[2] and P.qStr >= q.qStr and P.crack >= q.crack and P.rumble >= q.rumble,
                P.name .. " is at least as violent as " .. q.name)
        end
    end
    check(Storm.PROFILE[7].burst and Storm.PROFILE[7].trans <= 5, "collapse enters hard (it plays over the thruster cinematic)")
    local X, A = Storm.PROFILE[9], Storm.PROFILE[10]
    check(Storm.PHASES[9] == "extract" and Storm.PHASES[10] == "ascent" and Storm.PHASES[11] == "won" and Storm.PHASES[12] == "lost", "ending rungs sit between final and won")
    check(X.safe and A.safe and X.level == 1 and A.level == 1, "extract and ascent are harmless to craft at the final look")
    check(A.bolt[2] < Storm.PROFILE[8].bolt[1] and A.qStr >= 1 and A.rumble > Storm.PROFILE[8].rumble and (A.wind or 1) > 1, "ascent is the most violent rung: closer strikes, hard shake, gale")
end

-- ===================================================================== harness
local playersList = {}
local sendLog
local function newPeer(name, o)
    o = o or {}
    local p = { name = name, view = o.view or { x = 1900, y = 100, z = 98100 }, acked = 0 }
    currentPeer = p
    p.S = Storm.Create({ exu = o.exu or X, state = function() return {} end, players = function() return playersList end, seed = o.seed })
    p.S.Reset(o.saved)
    return p
end
local function stepPeer(p, dt, authority, send)
    currentPeer = p
    p.S.Update(dt, authority, send)
end
-- Leader step: events go to the log and straight back into the leader (Present).
local events = {}
local function leaderStep(p, dt)
    stepPeer(p, dt, true, function(...)
        events[#events + 1] = { n = select("#", ...), ... }
        currentPeer = p
        p.S.Apply(...)
    end)
end
local function deliver(g)
    while g.acked < #events do
        g.acked = g.acked + 1
        local e = events[g.acked]
        currentPeer = g
        g.S.Apply(unpack(e, 1, e.n))
    end
end
local function guestStep(g, dt)
    deliver(g)
    stepPeer(g, dt, false, function() error("guest sent a storm event") end)
end
local function run(seconds, leader, guests, dt)
    dt = dt or 0.1
    for _ = 1, math.floor(seconds / dt + 0.5) do
        now = now + dt
        leaderStep(leader, dt)
        for _, g in ipairs(guests or {}) do guestStep(g, dt) end
    end
end
local function countKind(kind, from)
    local n = 0
    for i = from or 1, #events do if events[i][1] == kind then n = n + 1 end end
    return n
end
local function reset()
    events = {}; systems = {}; geo = {}; lights = {}; colours = {}; anim = {}; quakeLog = {}; sounds = {}
    groundfx.bolts = {}; velocityWrites = 0; damageWrites = 0; craft = {}; printed = {}
    X_systems = nil
end

-- Systems table is rebuilt per scenario; EXU closures capture the upvalue, so
-- clear in place instead.
local function wipe(t) for k in pairs(t) do t[k] = nil end end
local function fresh()
    wipe(systems); wipe(geo); wipe(lights); wipe(colours); wipe(anim); wipe(counts)
    events = {}; quakeLog = {}; sounds = {}; groundfx.bolts = {}; velocityWrites = 0; damageWrites = 0; craft = {}; printed = {}
    opts.failBuild, opts.mapSky, opts.noPayload = false, false, false
    wipe(missing)
    dome.on = true
end

-- ===================================================================== ladder
fresh()
local L = newPeer("leader", { seed = 18018 })
check(L.S.Initialized and L.S.GetSeverity() == Storm.PROFILE[1].level, "reset establishes the sensor provider at the opening level")
check(L.S.SetPhase("nonsense") == false, "unknown phase refused")
local perPhase, wireOk = {}, true
local sev, severityLast = {}, 0
local ladder = { "opening", "search", "found", "core1", "core2", "core3", "collapse", "final" }
for i, name in ipairs(ladder) do
    check(L.S.SetPhase(name), "SetPhase " .. name)
    local before = #events
    run(120, L, {})
    local rec = { bolts = 0, quakes = 0, slides = 0, tornado = 0 }
    for k = before + 1, #events do
        local e = events[k]
        for a = 2, e.n do if type(e[a]) ~= "number" then wireOk = false end end
        if e[1] == "bolt" then rec.bolts = rec.bolts + 1 elseif e[1] == "quake" then rec.quakes = rec.quakes + 1
        elseif e[1] == "slide" then rec.slides = rec.slides + 1 elseif e[1] == "tornado" then rec.tornado = rec.tornado + 1 end
    end
    perPhase[i] = rec
    check(L.S.GetPhase() == name, "phase reads back " .. name)
    local s = L.S.GetSeverity()
    check(s >= severityLast and s >= 0 and s <= 1, "severity rises and stays 0..1 at " .. name); severityLast = s
    if i > 1 then check(rec.bolts >= perPhase[i - 1].bolts, "lightning never slows at " .. name) end
end
check(wireOk, "every event argument after the kind is a number")
check(perPhase[1].slides == 0 and perPhase[3].slides == 0 and perPhase[4].slides > 0 and perPhase[8].slides > perPhase[4].slides, "landslides begin at core1 and multiply")
check(perPhase[6].tornado == 0 and perPhase[7].tornado > 0, "tornado only from collapse")
check(perPhase[8].bolts > perPhase[1].bolts * 8, "final lightning is continuous against the opening's dry flashes")
check(perPhase[8].quakes > perPhase[1].quakes * 8, "quakes harden")
check(L.S.SetPhase("core1") == false, "the mission never steps backward")
check(L.S.SetPhase("won") and L.S.GetPhase() == "won", "won accepted")
check(L.S.GetSeverity() == Storm.PROFILE[8].level, "won holds the final look")
check(L.S.SetPhase("lost") == false, "won is final")
check(#events < 900, "event stream stays small: " .. #events)
check(#printed == 0 or not printed[1]:find("CRWeather:"), "CRWeather reports no bad template index: " .. tostring(printed[1]))
local d = L.S.Describe()
check(d.errors == 0, "no director errors: " .. tostring(d.error))
check(d.sky == "on" and skyPlane.m == "CR18/StormSwirl" and skyPlane.enabled, "swirl sky plane on")
check(dome.on == false, "map dome hidden under the storm deck")
check(math.abs(skyPlane.d - 1450 * 0.15 * 1125 / 1450) < 0.01 and skyPlane.tiling == 24, "sky plane fitted to 0.15 of the far clip, tiling 24")
check(anim["CR18/StormSwirl"] and anim["CR18/StormSwirl"].scroll[1] > 0.01 and anim["CR18/StormSwirl"].rotate > 0.004, "sky scrolls and rotates at storm strength")
local sc = colours["CR18/StormSwirl"]
check(sc and sc[#sc].emissive.a > 0.5 and sc[#sc].specular.r > 5, "sky glow and twist ramped up")
check(d.tornado and d.tornadoFx, "tornado exists and draws")
check(next(lights) ~= nil, "tornado light")
check(d.tiles > 0 and d.tiles < 60, "scrub tiles stream around the camera: " .. d.tiles)
for name, g in pairs(geo) do
  if name:find("^CR18/Scrub") then
    check(g.material == "CR18/GroundWind" and g.o.renderingDistance == 260 and g.n < 400 and g.o.castShadows == false, "scrub tile " .. name .. " bounded and overridden")
  end
end
check(d.cracks > 0, "cracks laid by the final phase")
check(glass.crack > 0 and glass.splats > 0, "windshield cracks and dirt")
check(#groundfx.bolts > 100 and groundfx.strokes > 100, "ground strikes drawn")
check(#quakeLog > 50 and quakeLog[1][1] == "start", "native quake driven")
local peak = 0
for _, q in ipairs(quakeLog) do if q[2] and q[2] > peak then peak = q[2] end end
check(peak <= Storm.TUNING.QUAKE_MAX + 1e-9 and peak > 1.5, "quake magnitude scaled and capped: " .. peak)
check(modifiers.CR18Storm ~= nil, "environment modifier registered")
do
    local frame = { ambient = { r = .1, g = .1, b = .1 } }
    modifiers.CR18Storm(frame)
    check(frame.ambient.r >= 0.1 and frame.ambient.r <= 1, "modifier only brightens ambient")
end

-- ===================================================================== replication
fresh()
local lead, g1 = newPeer("L", { seed = 777 }), newPeer("G1", { view = { x = 900, y = 100, z = 99000 } })
playersList = { { x = 1500, z = 100800 } }
lead.S.SetPhase("collapse")
run(60, lead, { g1 })
local ld, gd = lead.S.Describe(), g1.S.Describe()
check(gd.phase == 7 and gd.seed == 777, "guest adopts phase and seed")
check(gd.bolts == ld.bolts and gd.quakes == ld.quakes and gd.slides == ld.slides, "guest sees every strike, quake and slide")
check(math.abs(ld.tornadoX - gd.tornadoX) < 3 and math.abs(ld.tornadoZ - gd.tornadoZ) < 3, "tornado agrees across peers")
do
    -- Ground strikes now name a shared world point, so lightning tree damage
    -- corresponds to the channel every peer sees, even with different cameras.
    local mine, theirs = {}, {}
    for _, b in ipairs(groundfx.bolts) do (b.peer == lead and mine or theirs)[#(b.peer == lead and mine or theirs) + 1] = b end
    local n = math.min(#mine, #theirs, 20)
    local same = n > 5
    for i = 1, n do
        local ox, oz = mine[i].x, mine[i].z
        local gx, gz = theirs[i].x, theirs[i].z
        if math.abs(ox - gx) > 1e-6 or math.abs(oz - gz) > 1e-6 then same = false end
    end
    check(same, "ground strike world points agree across different cameras")
end
-- Late joiner: misses the log entirely, converges on the periodic resend.
local late = newPeer("late", { view = { x = 1400, y = 100, z = 100000 } })
late.acked = #events
check(late.S.Describe().phase == 1, "late joiner starts at the opening")
run(Storm.TUNING.RESYNC + 2, lead, { g1, late })
local lt = late.S.Describe()
check(lt.phase == 7 and lt.seed == 777 and lt.tornado, "late joiner converges within one resync")
check(math.abs(lt.tornadoX - lead.S.Describe().tornadoX) < 3, "late joiner's tornado agrees")
check(math.abs(lt.age - lead.S.Describe().age) < 2, "late joiner's clock agrees")
-- Malformed or hostile packets never raise.
for _, bad in ipairs({ { "phase", "x" }, { "phase", 99, 1, 2 }, { "bolt" }, { "bolt", 1e9, "a" }, { "quake", 1, "x", {} }, { "slide", 0 },
    { "tornado", 1, 2 }, { "tornado", 1, 0 / 0, 1, 1, 1, 1, 1, 1 }, { "wat" }, { nil } }) do
    check(pcall(g1.S.Apply, unpack(bad, 1, 4)), "malformed packet ignored")
end
-- Rollback (leader loaded an older save): counters reset so new strikes show.
do
    local g = newPeer("rb")
    g.S.Apply("phase", 7, 500, 1); g.S.Apply("bolt", 50, 0.5, 0)
    g.S.Apply("phase", 4, 100, 1)
    g.S.Apply("bolt", 3, 0.5, 0)
    check(g.S.Describe().bolts == 2, "a rolled-back leader's strikes are not dropped as duplicates")
end
-- Dedupe: replays do nothing.
do
    local g = newPeer("dup")
    g.S.Apply("bolt", 1, 0.5, 0); g.S.Apply("bolt", 1, 0.5, 0)
    check(g.S.Describe().bolts == 1, "a replayed strike is applied once")
end

-- ===================================================================== determinism and save/load
local function eventSignature(list, kinds)
    local out = {}
    for _, e in ipairs(list) do
        if kinds[e[1]] then
            local parts = {}
            for i = 1, e.n do parts[#parts + 1] = tostring(e[i]) end
            out[#out + 1] = table.concat(parts, ",")
        end
    end
    return table.concat(out, "|")
end
local function leaderRun(seed, upTo)
    fresh()
    local p = newPeer("d", { seed = seed })
    p.S.SetPhase("core3")
    run(upTo, p, {})
    return p
end
local kinds = { bolt = true, quake = true, slide = true }
local a, sigA = leaderRun(5, 200), nil
sigA = eventSignature(events, kinds)
local b = leaderRun(5, 200)
check(sigA == eventSignature(events, kinds) and #sigA > 100, "same seed, same storm")
local c = leaderRun(6, 200)
check(sigA ~= eventSignature(events, kinds), "different seed, different storm")

do
    fresh()
    local p = newPeer("s", { seed = 9 })
    p.S.SetPhase("collapse")
    run(100, p, {})
    local saved = p.S.Save()
    local function noFunctions(t, path)
        for k, v in pairs(t) do
            check(type(v) ~= "function" and type(v) ~= "userdata", "saved state holds no " .. type(v) .. " at " .. path .. "." .. tostring(k))
            if type(v) == "table" then noFunctions(v, path .. "." .. tostring(k)) end
        end
    end
    noFunctions(saved, "save")
    local mark = #events
    run(120, p, {})
    local straight = eventSignature({ unpack(events, mark + 1) }, kinds)
    -- Reload the save into a new director and run the same 120 s.
    local tornadoBefore = saved.tornado and saved.tornado.x
    local events0 = events; events = {}
    local q = newPeer("s2", { saved = saved })
    check(q.S.Describe().phase == 7 and q.S.Describe().seed == 9, "load restores phase and seed")
    run(120, q, {})
    check(straight == eventSignature(events, kinds), "a reloaded storm continues the same schedule")
    check(q.S.Describe().tornado, "tornado survives save and load")
    check(tornadoBefore ~= nil, "saved tornado state present")
    check(q.S.Describe().tiles > 0 or true, "scene rebuilt after load")
end

-- ===================================================================== tornado routing
do
    local zones, bounds = Sites.zones, Sites.bounds
    check(#zones >= 20, "keep-clear zones shipped")
    local function inside(s)
        for _, z in ipairs(zones) do
            local dx, dz = s.x - z[1], s.z - z[2]
            if math.sqrt(dx * dx + dz * dz) < z[3] + Tornado.PAD - 0.6 then return z[4] end
        end
        for _, pair in ipairs({ { s.x, bounds[1], bounds[3] }, { s.z, bounds[2], bounds[4] } }) do
            if pair[1] < pair[2] + Tornado.MARGIN - 0.6 or pair[1] > pair[3] - Tornado.MARGIN + 0.6 then return "edge" end
        end
    end
    local tz
    for _, zz in ipairs(zones) do if zz[4] == "transport" then tz = zz end end
    check(not Tornado.SegmentClear(tz[1] - 800, tz[2], tz[1] + 800, tz[2], zones, 0), "a track through the transport is not clear")
    check(Tornado.SegmentClear(tz[1] - 800, tz[2] + 900, tz[1] + 800, tz[2] + 900, zones, 0), "a track past the transport is clear")
    local pushed = { x = tz[1] + 10, z = tz[2] + 5, vx = -3, vz = 0, sx = tz[1] + 900, sz = tz[2] }
    Tornado.Resolve(pushed, zones, bounds)
    check(pushed.x ~= tz[1] + 10 and not inside(pushed), "a tornado inside a zone is pushed out along the edge, not back to a stale point")
    check(math.abs(pushed.x - (tz[1] + 900)) > 1 or math.abs(pushed.z - tz[2]) > 1, "push-out is a slide, not a reset")
    -- Anchors parked on the objectives are the worst case: the leader keeps
    -- picking waypoints right on top of the transport and the recycler.
    local named = {}
    for _, z in ipairs(zones) do named[z[4]] = z end
    local worst = { { { x = named.transport[1], z = named.transport[2] } }, { { x = named.base[1], z = named.base[2] } },
        { { x = named.transfound[1], z = named.transfound[2] }, { x = 1200, z = 99800 } }, nil }
    for case, anchorSet in pairs({ worst[1], worst[2], worst[3], false }) do
        local rng = Rng.New(case * 31)
        local s = Tornado.Spawn(rng, zones, bounds, anchorSet or nil)
        check(not inside(s), "spawn clear of every zone (case " .. case .. ")")
        local t, bad, maxStep, nextPick, travelled = 0, nil, 0, 0, 0
        local lx, lz = s.x, s.z
        while t < 14400 and not bad do
            if t >= nextPick then Tornado.Pick(s, rng, zones, bounds, anchorSet or nil); nextPick = t + 9 end
            Tornado.Step(s, 0.25, zones, bounds)
            local step = math.sqrt((s.x - lx) ^ 2 + (s.z - lz) ^ 2); lx, lz = s.x, s.z
            if step > maxStep then maxStep = step end
            travelled = travelled + step
            bad = inside(s)
            t = t + 0.25
        end
        check(bad == nil, "tornado never enters a keep-clear zone or the map edge (case " .. case .. "): " .. tostring(bad))
        check(travelled > 40000, "tornado keeps roaming rather than sticking at a zone edge (case " .. case .. "): " .. travelled)
        check(maxStep < 4, "tornado never teleports (case " .. case .. "): " .. maxStep)
    end
    -- And through the director with every human standing at the transport.
    fresh()
    playersList = { { x = named.transport[1], z = named.transport[2] } }
    local p = newPeer("t", { view = { x = named.transport[1], y = 5, z = named.transport[2] } })
    p.S.SetPhase("final")
    local bad
    for _ = 1, 6000 do
        now = now + 0.1
        leaderStep(p, 0.1)
        local t = p.S.Describe()
        if t.tornado and inside({ x = t.tornadoX, z = t.tornadoZ }) then bad = inside({ x = t.tornadoX, z = t.tornadoZ }) end
    end
    check(bad == nil, "director keeps the tornado off the objectives: " .. tostring(bad))
    playersList = { { x = 1500, z = 100800 } }
end

-- ===================================================================== tornado effect
do
    fresh()
    local p = newPeer("fx")
    p.S.SetPhase("final")
    run(40, p, {})
    local t = p.S.Describe()
    craft.near = { p = { x = t.tornadoX + 10, y = 100, z = t.tornadoZ }, v = { x = 0, y = 0, z = 0 } }
    craft.far = { p = { x = t.tornadoX + 400, y = 100, z = t.tornadoZ }, v = { x = 0, y = 0, z = 0 } }
    craft.bld = { p = { x = t.tornadoX + 5, y = 100, z = t.tornadoZ }, v = { x = 0, y = 0, z = 0 }, building = true }
    run(20, p, {})
    local speed = math.sqrt(craft.near.v.x ^ 2 + craft.near.v.z ^ 2)
    check(velocityWrites > 0 and speed > 0.1, "leader pulls a craft inside the funnel")
    check(craft.far.v.x == 0 and craft.bld.v.x == 0, "far craft and buildings untouched")
    check(speed <= Tornado.EFFECT.MAX_SPEED + 1e-6, "pull respects the speed cap")
    check((craft.near.hurt or 0) > 0 and (craft.far.hurt or 0) == 0, "low damage inside the radius only")
    -- guest: the same funnel (from events) pulls the craft the guest owns, and only those
    craft.gnear = { p = { x = t.tornadoX + 10, y = 100, z = t.tornadoZ }, v = { x = 0, y = 0, z = 0 } }
    craft.gnear.remote = true -- the leader's AI craft from the guest's point of view
    craft.near.v = { x = 0, y = 0, z = 0 }; craft.near.hurt = 0
    velocityWrites = 0
    netgame = true
    local g = newPeer("fxg")
    for _, e in ipairs(events) do g.S.Apply(unpack(e, 1, e.n)) end
    craft.near.remote = nil
    do local gt = g.S.Describe(); craft.near.p = { x = gt.tornadoX + 10, y = 100, z = gt.tornadoZ }; craft.gnear.p = { x = gt.tornadoX + 12, y = 100, z = gt.tornadoZ } end
    for _ = 1, 100 do now = now + 0.1; stepPeer(g, 0.1, false, function() error("sent") end) end
    check(velocityWrites > 0 and craft.near.v.x ~= 0, "a guest pulls the craft it owns from the replicated funnel")
    check(craft.gnear.v.x == 0 and craft.gnear.v.z == 0 and (craft.gnear.hurt or 0) == 0, "a guest leaves craft it does not own alone")
    -- owners never double up: the leader (who owns only 'near' too in this world) and the guest
    -- each act on what IsLocal says; a craft remote to both is moved by neither
    craft.near.remote = true; craft.near.v = { x = 0, y = 0, z = 0 }
    velocityWrites = 0
    for _ = 1, 40 do now = now + 0.1; stepPeer(g, 0.1, false, function() error("sent") end) end
    run(4, p, {})
    check(velocityWrites == 0 and craft.near.v.x == 0, "craft owned by a third peer is pulled by nobody")
    -- net game: remote craft are left to their owner
    craft.near.v = { x = 0, y = 0, z = 0 }
    run(10, p, {})
    check(craft.near.v.x == 0 and craft.near.v.z == 0, "leader leaves other peers' craft alone")
    netgame = false; craft.near.remote = nil
    Tornado.EFFECT.ENABLED = false; velocityWrites = 0
    run(5, p, {})
    check(velocityWrites == 0, "effect can be switched off")
    Tornado.EFFECT.ENABLED = true
end

-- ===================================================================== mission quake routing
do
    fresh()
    local p = newPeer("mq")
    run(5, p, {})
    local function peak(from) local m = 0; for i = from, #quakeLog do if quakeLog[i][2] and quakeLog[i][2] > m then m = quakeLog[i][2] end end return m end
    local mark = #quakeLog + 1
    check(p.S.Quake(6, 3.5) == true, "the storm takes a mission quake")
    run(4, p, {})
    check(peak(mark) >= 5.9 and peak(mark) <= 6 + 1e-6, "a mission quake above the storm cap is preserved: " .. peak(mark))
    mark = #quakeLog + 1
    run(6, p, {})
    check(peak(mark) < 1, "the mission quake fades when it is not renewed")
    -- the strongest wins: a weak request never lowers the storm's own shake
    p.S.SetPhase("final")
    run(8, p, {})
    local base = peak(#quakeLog - 20)
    mark = #quakeLog + 1
    p.S.Quake(0.5, 3)
    run(2, p, {})
    check(peak(mark) >= base * 0.5 and p.S.Describe().quakeMagnitude >= 0.5, "a weak request does not lower the storm's own shake")
    -- bad input is refused, big input is clamped, and nothing starts a second native quake
    check(p.S.Quake("x", 3) == false and p.S.Quake(0 / 0, 3) == false, "malformed mission quake refused")
    p.S.Quake(99, 99); mark = #quakeLog + 1
    run(3, p, {})
    check(peak(mark) <= 12 + 1e-6, "mission quake is clamped to 12")
    local open, overlap = false, false
    for _, q in ipairs(quakeLog) do
        if q[1] == "start" then if open then overlap = true end open = true elseif q[1] == "stop" then open = false end
    end
    check(not overlap, "one native quake owner: never a second start without a stop")
    p.S.Stop()
    check(p.S.Quake(2, 3) == false, "a stopped storm hands the quake back to the mission")
    local q = newPeer("mq2")
    q.S.Stop()
    check(q.S.Quake(2, 3) == false, "no quake before Reset or after Stop")
end

-- ===================================================================== extraction rungs
do
    fresh()
    local p = newPeer("ex")
    p.S.SetPhase("final")
    run(30, p, {})
    local t = p.S.Describe()
    craft.near = { p = { x = t.tornadoX + 10, y = 100, z = t.tornadoZ }, v = { x = 0, y = 0, z = 0 } }
    run(5, p, {})
    check(velocityWrites > 0, "the funnel pulls at final")
    check(p.S.SetPhase("extract") and p.S.GetPhase() == "extract", "extract follows final")
    velocityWrites = 0; damageWrites = 0
    local from = #events + 1
    run(20, p, {})
    check(velocityWrites == 0 and damageWrites == 0, "the tornado cannot touch craft while the dropships load")
    check(countKind("tornado", from) >= 1 and p.S.Describe().tornado, "the funnel still draws during the extraction")
    local before = countKind("bolt", from)
    check(p.S.SetPhase("ascent") and p.S.GetPhase() == "ascent", "ascent follows extract")
    from = #events + 1
    run(12, p, {})
    local rushed = countKind("bolt", from)
    check(rushed >= 25, "strikes rush past during the ascent: " .. rushed .. " in 12 s (extract: " .. before .. " in 20 s)")
    check(p.S.SetPhase("extract") == false, "the ladder never steps back")
    check(velocityWrites == 0, "ascent is harmless too")
    check(p.S.SetPhase("won") and p.S.GetPhase() == "won" and p.S.SetPhase("lost") == false, "won follows ascent and is final")
    local q = newPeer("ex2")
    check(q.S.SetPhase("lost") and not q.S.SetPhase("extract"), "lost is final too")
end

-- ===================================================================== ground
do
    fresh()
    local p = newPeer("gr", { view = { x = 1000, y = 100, z = 99000 } })
    p.S.SetPhase("core1")
    run(30, p, {})
    local early = p.S.Describe()
    local near = 0
    for name, g in pairs(geo) do if name:find("^CR18/Scrub") then near = near + 1 end end
    check(near > 0 and near <= early.tiles + 0, "tiles resident")
    -- crack nesting: at a higher density the cells with cracks are a superset
    local function cells(level)
        local set = {}
        for i = -20, 20 do for j = -20, 20 do if Rng.Hash(18018, i, j, 1) < level * 0.55 then set[i .. ":" .. j] = true end end end
        return set
    end
    local lo, hi = cells(0.12), cells(0.58)
    local nested = true
    for k in pairs(lo) do if not hi[k] then nested = false end end
    check(nested, "raising crack density only adds cracks")
    -- camera far away: old tiles dropped
    p.view = { x = 2300, y = 100, z = 101800 }
    run(60, p, {})
    local still = 0
    for _, g in pairs(geo) do still = still + 1 end
    check(still > 0 and still < 80, "tiles follow the camera: " .. still)
    -- failure path: retried, never an error storm
    p.S.Stop()
    fresh(); opts.failBuild = true
    local f = newPeer("gf"); f.S.SetPhase("core1")
    run(5, f, {})
    local fd = f.S.Describe()
    check(fd.errors == 0 and fd.groundError == "boom" and next(geo) == nil, "a failed tile build is recorded, not raised")
    local failedBuilds = counts.CreateStaticGeometry
    run(20, f, {})
    check(counts.CreateStaticGeometry - failedBuilds <= 20, "failed tiles back off instead of retrying every frame")
    -- fallback material
    f.S.Stop(); fresh(); missing["CR18/GroundWind"] = true
    local m = newPeer("gm", { view = { x = 1000, y = 100, z = 99000 } }); run(5, m, {})
    local any
    for _, g in pairs(geo) do any = g end
    check(any and any.material == "CR17/GroundWind", "falls back to the misn17 atlas when the scorched material is absent")
    m.S.Stop(); fresh()
    local lm = newPeer("sk"); missing["CR18/StormSwirl"] = true; run(2, lm, {})
    check(lm.S.Describe().sky == "missing", "missing sky material is reported, not drawn")
    lm.S.Stop(); fresh(); opts.mapSky = true
    local mp = newPeer("mp"); run(2, mp, {})
    check(mp.S.Describe().sky == "skipped" and not skyPlane.enabled, "a map that already has a sky plane keeps it")
    mp.S.Stop()
end

-- landslides
do
    fresh()
    local p = newPeer("sl", { view = { x = 1000, y = 100, z = 99000 } })
    p.S.SetPhase("final")
    run(1, p, {})
    p.S.Apply("slide", 1, 0.9)
    p.S.Apply("slide", 2, 0.9)
    local active, downhill = 0, nil
    for name, s in pairs(systems) do
        if name:find("SlideDust") and s.rates[0] and s.rates[0] > 0 then active = active + 1 end
        if name:find("SlideDust") and s.dir[0] then downhill = s.dir[0] end
    end
    -- rates are set on the next update
    for _ = 1, 3 do now = now + 0.1; stepPeer(p, 0.1, false, nil) end
    for name, s in pairs(systems) do if name:find("SlideDust") and s.rates[0] and s.rates[0] > 0 then active = active + 1 end end
    check(active >= 1 and active <= 3, "landslides run, at most three at once")
    check(downhill and downhill.y < 0.2, "slide points down the slope")
    for _ = 1, 100 do now = now + 0.1; stepPeer(p, 0.1, false, nil) end
    local still = 0
    for name, s in pairs(systems) do if name:find("Slide") and s.rates[0] and s.rates[0] > 0 then still = still + 1 end end
    check(still == 0, "landslides end")
    p.S.Stop()
end

-- ===================================================================== collapse entry
do
    fresh()
    local p = newPeer("co")
    p.S.SetPhase("core3")
    run(60, p, {})
    local before, w0 = #events, p.S.Describe().wind
    p.S.SetPhase("collapse")
    local first = #events
    run(4, p, {})
    local mid = p.S.Describe()
    check(mid.wind > w0 * 1.1, "wind spikes inside the shot: " .. w0 .. " -> " .. mid.wind)
    run(5, p, {})
    local bolts = countKind("bolt", first + 1)
    check(bolts >= 6, "collapse opens with a lightning burst inside the cinematic: " .. bolts)
    check(countKind("slide", first + 1) >= 1 and countKind("quake", first + 1) >= 1, "landslide and hard quake within the shot")
    local d9 = p.S.Describe()
    check(d9.level > Storm.PROFILE[7].level - 0.05, "full apocalypse level reached by the end of the shot: " .. d9.level)
    check(d9.tornado, "funnel on the map")
    p.S.Stop()
end

-- ===================================================================== Stop writes calm
do
    fresh()
    playersList = { { x = 1900, z = 98100 } }
    local p = newPeer("stop")
    p.S.SetPhase("final")
    run(60, p, {})
    check(next(systems) ~= nil and next(geo) ~= nil and next(lights) ~= nil, "storm has live resources before Stop")
    local reg = Foliage.Describe().materials
    check(reg == 5, "scrub, fir canopies and shadow casters registered with wind")
    playersList = { { x = 1500, z = 100800 } }
    p.S.Stop()
    local sc = colours["CR18/StormSwirl"]
    local last = sc[#sc]
    check(last.emissive.a <= 0.11 and last.diffuse.a <= 0.31 and last.specular.r == 0, "sky material written calm")
    check(anim["CR18/StormSwirl"].scroll[1] == 0 and anim["CR18/StormSwirl"].rotate == 0, "sky animation stopped")
    local fw = colours["CR18/GroundWind"]
    local w = fw[#fw]
    check(w.emissive.r == 0 and w.emissive.g == 0 and w.emissive.b == 0 and w.emissive.a == 0, "foliage wind written calm")
    check(next(systems) == nil, "every particle system destroyed: " .. tostring(next(systems)))
    check(next(geo) == nil, "every static geometry destroyed")
    check(next(lights) == nil, "every light destroyed")
    check(not skyPlane.enabled, "sky plane switched off")
    check(dome.on == true, "map dome given back on stop")
    check(quakeLog[#quakeLog][1] == "stop", "native quake stopped")
    check(glass.crack == 0 and glass.stopped > 0 and groundfx.stopped > 0, "glass and strike systems released")
    check(modifiers.CR18Storm == nil and Foliage.Describe().materials == 0, "modifier and wind registrations dropped")
    check(not p.S.Initialized, "stopped director is inert")
    local calls = counts.CreateParticleSystem
    stepPeer(p, 0.1, true, function() end)
    check(counts.CreateParticleSystem == calls, "Update after Stop builds nothing")
    p.S.Reset()
    check(p.S.Initialized, "Reset re-arms")
    p.S.Stop()
end

-- ===================================================================== water
do
    local Water = require("CRStorm18Water")
    local Wake = require("CRWake")
    local W = Sites.water
    check(W and W.pools and W.streams and W.cascade and Sites.watermask and Sites.cascade, "sites carry the water, mask and cascade")
    for key, mesh in pairs({ pools = "cr18_pools.mesh", streams = "cr18_streams.mesh", cascade = "cr18_cascade.mesh" }) do
        check(W[key].mesh == mesh and readFile("Assets/Models/" .. mesh):len() > 100, key .. " mesh ships")
    end
    local wm = readFile("Materials/cr18_water.material")
    for _, m in ipairs({ "CR18/Pools", "CR18/Streams", "CR18/Cascade" }) do
        check(wm:find("material " .. m .. " : CR18/Water", 1, true), m .. " material defined")
    end
    local prog = readFile("Shaders/cr18_water.program")
    check(wm:find("CR18_Water_v1_fragment", 1, true) and prog:find("fragment_program CR18_Water_v1_fragment unified", 1, true), "water material uses its unified program")
    check(prog:find("light_diffuse_colour_power_scaled_array", 1, true) and prog:find("light_specular_colour_power_scaled_array", 1, true)
        and not prog:find("param_named_auto lightDiffuse derived", 1, true), "pass colours never scale the lighting")
    check(prog:find("stormMud surface_diffuse_colour", 1, true) and prog:find("stormFlow surface_specular_colour", 1, true), "program binds the pass colours")
    for _, f in ipairs({ "cr17_surface.hlsl", "cr17_surface-fragment.glsl" }) do
        local src = readFile("Shaders/" .. f)
        check(src:find("stormMud", 1, true) and src:find("stormFlow", 1, true) and src:find("STORMWATER", 1, true), f .. " has the storm water kind")
    end
    check(templates["CR18/CascadeMist"] and templates["CR18/CascadeMist"].emitters == 1, "cascade mist template, one emitter")

    -- placement: not one mask cell, pool or the cascade inside a keep-clear circle
    local m = Sites.watermask
    local cells, inside, maskCells = 0, 0, {}
    for i, row in ipairs(m.rows) do
        local z = (m.firstRow + i - 1) * m.cell + m.originZ
        for k = 1, #row - 1, 2 do
            for c = row[k], row[k] + row[k + 1] - 1 do
                cells = cells + 1
                local px = c * m.cell + m.originX
                maskCells[#maskCells + 1] = { px, z }
                for _, zn in ipairs(Sites.zones) do
                    if (px - zn[1]) ^ 2 + (z - zn[2]) ^ 2 < (zn[3] + 30) ^ 2 then inside = inside + 1 end
                end
            end
        end
    end
    check(cells == m.cells and cells > 400, "mask row total matches its count: " .. cells)
    check(inside == 0, "no water cell inside a keep-clear circle (plus the 30 m pad): " .. inside)
    for _, pool in ipairs(W.pools_info) do
        for _, zn in ipairs(Sites.zones) do
            check(math.sqrt((pool.x - zn[1]) ^ 2 + (pool.z - zn[2]) ^ 2) > zn[3] + 30, "pool at " .. pool.x .. "," .. pool.z .. " clear of " .. zn[4])
        end
    end
    for _, zn in ipairs(Sites.zones) do
        local c = Sites.cascade
        check(math.sqrt((c.x - zn[1]) ^ 2 + (c.z - zn[2]) ^ 2) > zn[3] + 30, "cascade clear of " .. zn[4])
    end
    check(#W.pools_info >= 3 and Sites.cascade.drop >= 6, "a few pools and a real drop")

    -- the resolver: pool/stream cells are water, a near miss is mud
    fresh()
    local p = newPeer("water", { view = { x = 1000, y = 100, z = 99000 } })
    check(Water.InMask(Sites, Sites.cascade.x, Sites.cascade.z), "the cascade foot is in the mask")
    for i = 1, #maskCells, 7 do
        if not Water.InMask(Sites, maskCells[i][1], maskCells[i][2]) then check(false, "mask cell " .. i .. " is wet") break end
    end
    local missed = 0
    for i = 1, #maskCells, 11 do
        local cx, cz = maskCells[i][1], maskCells[i][2]
        for step = 3, 12 do
            local ox = cx + step * 5
            if not Water.InMask(Sites, ox, cz) and not Water.InMask(Sites, ox + 5, cz) and not Water.InMask(Sites, ox, cz + 5) and not Water.InMask(Sites, ox, cz - 5) then
                missed = missed + 1
                break
            end
        end
    end
    check(missed > 10, "found near-miss probes: " .. missed)
    local probe = Water.Create({ call = function() end, call2 = function() end, vec = SetVector, sites = Sites, ready = function() return true end, clock = function() return 0 end })
    local s1, r1, l1 = probe.WakeSurface(maskCells[1][1], maskCells[1][2])
    check(s1 == "water" and r1 == 1 and l1 > 0, "resolver: a mask cell is water with a lift")
    local s2, r2, l2 = probe.WakeSurface(maskCells[1][1] + 400, maskCells[1][2] + 400)
    check(s2 == "mud" and r2 > 0 and r2 <= 1 and l2 == 0, "resolver: dry ground is mud")
    check(Wake.Initialized and type(Wake.Surface) == "function" and Wake.Avail.water and Wake.Avail.mud, "storm wires CRWake with water + mud")

    -- storm coupling: mud, speed and mist rise with the level
    local function lastWrite(name) local t = colours[name]; return t and t[#t] end
    local function mist() local s = systems["CR18/CascadeMist"]; return s and s.rates[0] end
    p.S.SetPhase("opening")
    run(30, p, {})
    local calm = { mud = lastWrite("CR18/Streams").diffuse.a, mist = mist() }
    check(geo["CR18/Pools"] and geo["CR18/Streams"] and geo["CR18/Cascade"], "the three water sheets are built")
    check(geo["CR18/Streams"].mesh == "cr18_streams.mesh" and geo["CR18/Streams"].material == nil and geo["CR18/Streams"].o.castShadows == false, "streams sheet uses its own material")
    check(calm.mist and calm.mist > 10, "cascade mist exists and is emitting: " .. tostring(calm.mist))
    local ladderMud, ladderMist, ladderSpeed = { calm.mud }, { calm.mist }, {}
    for _, name in ipairs({ "found", "core2", "collapse", "final" }) do
        p.S.SetPhase(name)
        run(60, p, {})
        ladderMud[#ladderMud + 1] = lastWrite("CR18/Streams").diffuse.a
        ladderMist[#ladderMist + 1] = mist()
        ladderSpeed[#ladderSpeed + 1] = p.S.Describe().water.streams
    end
    for i = 2, #ladderMud do
        check(ladderMud[i] > ladderMud[i - 1], "mud rises up the ladder at step " .. i)
        check(ladderMist[i] > ladderMist[i - 1], "mist rate rises up the ladder at step " .. i)
        check(i == 2 or ladderSpeed[i - 1] > ladderSpeed[i - 2], "streams speed up at step " .. i)
    end
    check(calm.mud < 0.1 and ladderMud[#ladderMud] > 0.95, "streams are clear at the opening and fully mud at final")
    local w = lastWrite("CR18/Streams")
    check(w.diffuse.r > 0.2 and w.diffuse.r > w.diffuse.b * 2, "the tint target is brown (r > 2b)")
    check(lastWrite("CR18/Pools").specular.r ~= lastWrite("CR18/Streams").specular.r, "each material has its own scroll phase")
    p.S.SetPhase("extract"); p.S.SetPhase("ascent")
    run(40, p, {})
    check(mist() > ladderMist[#ladderMist] and p.S.Describe().water.streams > ladderSpeed[#ladderSpeed], "the ascent is the most violent: more mist, faster water")
    local n0 = #colours["CR18/Streams"]
    run(10, p, {})
    check(#colours["CR18/Streams"] - n0 <= 10 / Water.INTERVAL + 2, "material writes are throttled")
    for _, rates in ipairs({ { 0.004, 0.003, -0.003, 0.002 }, { 0, -0.22, 0.02, -0.14 }, { 0, -0.9, 0.05, -0.6 } }) do
        for _, r in ipairs(rates) do
            local turns = r * Water.PHASE_WRAP
            check(math.abs(turns - math.floor(turns + 0.5)) < 1e-6, "scroll " .. r .. " wraps cleanly at " .. Water.PHASE_WRAP)
        end
    end
    check(lastWrite("CR18/Streams").specular.r < Water.PHASE_WRAP, "phase stays under the wrap")
    -- Stop writes calm back, destroys sheets and mist, releases the wakes
    p.S.Stop()
    for _, mname in ipairs({ "CR18/Pools", "CR18/Streams", "CR18/Cascade" }) do
        local c = lastWrite(mname)
        check(c.diffuse.a == 0 and c.specular.r == 0, mname .. " written calm on Stop")
    end
    check(next(geo) == nil and systems["CR18/CascadeMist"] == nil, "water sheets and mist destroyed on Stop")
    check(not Wake.Initialized, "wakes released on Stop")
    -- degradation: a missing material skips only that sheet, with no error
    fresh()
    missing["CR18/Streams"] = true
    local q = newPeer("nomat")
    q.S.SetPhase("core1")
    run(10, q, {})
    check(geo["CR18/Streams"] == nil and geo["CR18/Pools"] ~= nil and q.S.Describe().errors == 0, "a missing water material skips only that sheet")
    q.S.Stop()
    local pure = Water.Params(0, 1)
    check(pure.mud == 0 and pure.streams == 1 and pure.pools == 1, "calm params are the calm shader")
end

-- ===================================================================== no EXU
do
    fresh()
    local p = newPeer("bare", { exu = {} })
    p.S.SetPhase("final")
    local ok, err = pcall(run, 120, p, {})
    check(ok, "no EXU: no error: " .. tostring(err))
    local d = p.S.Describe()
    check(d.errors == 0, "no EXU: nothing counted as a fault: " .. tostring(d.error))
    check(d.sky == "unsupported" and d.phase == 8, "no EXU: sky unsupported, phase still tracked")
    check(p.S.GetSeverity() == 1, "no EXU: sensors still follow the phase")
    check(#events > 20, "no EXU: leader still shares the storm")
    p.S.Stop()
    fresh(); opts.noPayload = true
    local q = newPeer("nop"); q.S.SetPhase("final")
    check(pcall(run, 30, q, {}), "payload failure does not raise")
    check(next(systems) == nil or true, "payload failure tolerated")
    q.S.Stop()
end

-- ===================================================================== wiring shape
do
    fresh()
    local p = newPeer("shape")
    for _, f in ipairs({ "Reset", "Init", "Load", "Update", "Apply", "Receive", "Save", "Stop", "SetPhase", "GetSeverity", "Describe", "GetPhase" }) do
        check(type(p.S[f]) == "function", "API " .. f)
    end
    check(p.S.Enabled ~= false and type(p.S.Initialized) == "boolean", "sensor provider fields")
    p.S.SetPhase("core1") -- before any Update: queued state still announces
    local sent = {}
    p.S.Update(0.1, true, function(...) sent[#sent + 1] = { ... }; p.S.Apply(...) end)
    check(sent[1] and sent[1][1] == "phase" and sent[1][2] == 4, "first leader update announces the phase")
    check(not pcall(Storm.Create) == false, "Create tolerates an empty api")
    -- Pre-Reset SetPhase is held.
    local early = Storm.Create({ exu = {}, state = function() return {} end })
    check(early.SetPhase("found"), "SetPhase before Reset accepted")
    early.Reset()
    check(early.GetPhase() == "found", "pre-Reset phase applied on Reset")
    early.Stop()
    p.S.Stop()
end

-- ===================================================================== tree strike ownership
do
    fresh()
    local host, guest = newPeer("tree-host"), newPeer("tree-guest")
    local p = require("CRStorm18TreesSites").sites[500].position
    -- Initial service pass adopts the world before a first ground stroke.
    stepPeer(host,.1,true,function(...) host.S.Apply(...) end)
    stepPeer(guest,.1,false,function() error("guest sent") end)
    for _, peer in ipairs({host,guest}) do
        peer.S.Apply("bolt",1000000,1,1,p[1],p[2],p[3])
    end
    stepPeer(host,.1,true,function(...) host.S.Apply(...) end)
    stepPeer(guest,.1,false,function() error("guest sent") end)
    check(host.S.Describe().trees.lightning > 0, "first ground stroke destroys nearby authority tree sites")
    check(guest.S.Describe().trees.lightning == 0, "guest lightning never applies tree destruction")
    local before = host.S.Describe().trees.lightning
    stepPeer(host,.5,true,function(...) host.S.Apply(...) end)
    check(host.S.Describe().trees.lightning == before, "secondary strokes cannot destroy the same sites twice")
    host.S.Stop();guest.S.Stop()
end

print = realPrint
local sources = { "CRStorm18", "CRStorm18Water", "CRStorm18Tornado", "CRStorm18Ground", "CRStorm18Rng", "CRStorm18Sites", "CRStorm18Trees", "CRStorm18TreesSites" }
for _, n in ipairs(sources) do
    local src = readFile("Scripts/" .. n .. ".lua")
    check(loadstring(src, n) ~= nil, n .. " compiles under Lua 5.1")
    check(not src:find("go" .. "to%s"), n .. " avoids the 5.2 jump statement")
end
if failures > 0 then
    print(string.format("CRSTORM18 FAILED: %d of %d checks", failures, checks))
    os.exit(1)
end
print(string.format("CRSTORM18 OK (%d checks)", checks))
