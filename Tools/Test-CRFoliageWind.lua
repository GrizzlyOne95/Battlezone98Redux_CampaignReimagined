-- Test-CRFoliageWind.lua
--
-- Drives the real CRWeather.lua and CRFoliageWind.lua against a recording exu
-- stub: the wind the sway shaders receive, which pass colour carries it, that
-- it is written only when it changes, that leaves fall only near foliage, and
-- that teardown leaves every material still (Ogre materials outlive the Lua
-- state, so a bent material would carry into the next mission).
--
-- Usage, from the repository root:
--
--     lua Tools/Test-CRFoliageWind.lua Scripts
--
-- Prints FOLIAGE WIND OK on success; prints each failed expectation and exits 1
-- otherwise.

local scriptDir = ... or "Scripts"
package.path = scriptDir .. "\\?.lua;" .. scriptDir .. "/?.lua;" .. package.path

local rec = { colors = {}, writes = 0, systems = {}, rates = {}, forces = {}, attached = {} }
local camera = { x = 0, y = 0, z = 0 }

local exu = {}
setmetatable(exu, { __index = function() return nil end })
exu.GetFog = function() return { r = 0.5, g = 0.4, b = 0.3, fogStart = 100, fogEnd = 800 } end
exu.SetFog = function() return true end
exu.GetAmbientLight = function() return { r = 0.5, g = 0.5, b = 0.5 } end
exu.SetAmbientLight = function() return true end
exu.GetSunDiffuse = function() return { r = 0.6, g = 0.6, b = 0.6 } end
exu.SetSunDiffuse = function() return true end
exu.GetSunPowerScale = function() return 1.0 end
exu.SetSunPowerScale = function() return true end
exu.GetCameraTransformMatrix = function()
    return { posit_x = camera.x, posit_y = camera.y, posit_z = camera.z }
end

exu.SetMaterialPassColors = function(name, colors, technique, pass, group, glow)
    assert(technique == -1 and pass == -1 and glow == true, "every technique, pass and the glow scheme")
    local slot, value = next(colors)
    assert(next(colors, slot) == nil, "one colour slot per write")
    rec.colors[name] = { slot = slot, r = value.r, g = value.g, b = value.b, a = value.a }
    rec.writes = rec.writes + 1
    return true
end

exu.CreateParticleSystem = function(name, template) rec.systems[name] = template return true end
exu.DestroyParticleSystem = function(name) rec.systems[name] = nil return true end
exu.DetachParticleSystem = function(name) rec.attached[name] = nil return true end
exu.AttachParticleSystemToCamera = function(name) rec.attached[name] = true return true end
exu.SetParticleSystemKeepLocalSpace = function() return true end
exu.SetParticleSystemNonVisibleUpdateTimeout = function() return true end
exu.SetParticleSystemParticleQuota = function() return true end
exu.SetParticleEmitterEmissionRate = function(name, index, rate) rec.rates[name] = rate return true end
exu.SetParticleEmitterDirection = function() return true end
exu.SetParticleEmitterVelocity = function() return true end
exu.SetParticleEmitterEnabled = function() return true end
exu.SetParticleEmitterParameter = function() return true end
exu.SetParticleAffectorParameter = function(name, index, parameter, value)
    if name == "CR/LeafLitter/Live" and index == 0 and parameter == "force_vector" then
        rec.forces[name] = value
    end
    return true
end

package.preload["exu"] = function() return exu end
package.preload["CRParticleTemplates"] = function()
    return { Ensure = function() return true end, EnsureExtra = function(name) return name == "cr_foliage" end }
end

function SetVector(x, y, z) return { x = x, y = y, z = z } end

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        print("FAIL: " .. message)
    end
end
local function near(a, b, tolerance)
    return type(a) == "number" and math.abs(a - b) <= (tolerance or 1e-3)
end

local Presets = require("CRWeatherPresets")
local CRWeather = require("CRWeather")
local Foliage = require("CRFoliageWind")

Presets.Presets.FoliageTestGale = {
    name = "FoliageTestGale",
    wind = { x = 0.0, y = -1.0, z = 0.5 },  -- leans like rain: y must not leak into the sway
    windSpeed = 12.0,
    gusts = { period = 8.0, depth = 0.5 },
    precipitation = {},
}

CRWeather.Init({ debug = false })

-- A still world before any wind material is registered writes nothing.
CRWeather.Update(0.1)
check(rec.writes == 0, "no material is touched before one registers")

-- Registration writes calm at once, so a material bent by a previous mission straightens.
check(Foliage.Register("CR17/LeavesWind") == true, "CR17 material registers")
check(Foliage.Register("CR/GrassWind", { slot = "specular" }) == true, "grass material registers")
check(Foliage.Register("Bad", { slot = "diffuse" }) == false, "a slot the shaders do not read is refused")
check(rec.colors["CR17/LeavesWind"].slot == "emissive" and rec.colors["CR17/LeavesWind"].a == 0,
    "CR17 wind rides the emissive colour and starts still")
check(rec.colors["CR/GrassWind"].slot == "specular", "grass wind rides specular, which CR_Textured never reads")

-- Calm weather: registered but still.
CRWeather.Update(0.1)
check(rec.colors["CR17/LeavesWind"].r == 0 and rec.colors["CR17/LeavesWind"].b == 0, "no preset means no sway")

-- A gale. Weight ramps over the transition, then wind is horizontal at full speed.
CRWeather.SetPreset("FoliageTestGale", 1.0)
for _ = 1, 30 do CRWeather.Update(0.1) end
local leaves = rec.colors["CR17/LeavesWind"]
check(near(leaves.r, 0.0, 0.01) and near(leaves.b, 12.0, 0.06),
    "sway takes the bearing from xz and the magnitude from GetWindSpeed: " .. tostring(leaves.r) .. "," .. tostring(leaves.b))
check(leaves.a == 1.0, "full scale once registered")
check(leaves.g >= 0 and leaves.g <= 0.5, "gust stays within the preset's depth")
check(near(CRWeather.GetGust(), leaves.g, 0.021), "the shader sees CRWeather's own gust")

-- Unchanged wind is not rewritten every frame.
local writes = rec.writes
CRWeather.Update(0.001)
check(rec.writes == writes, "an unchanged wind writes nothing")

-- A director's override wins, as for the particles.
CRWeather.SetWindOverride({ x = 1.0, y = -1.0, z = 0.0 }, 6.0)
CRWeather.Update(0.001)
leaves = rec.colors["CR17/LeavesWind"]
check(near(leaves.r, 6.0, 0.06) and near(leaves.b, 0.0, 0.06), "the override bearing and speed reach the sway")
CRWeather.ClearWindOverride()

-- Leaf litter: shed over foliage, nothing over bare ground.
local points = {}
for i = 1, 80 do points[i] = { 10 + (i % 9), 0, 10 + math.floor(i / 9) } end
Foliage.EnableLitter(points, { rate = 40, saturation = 40, minSpeed = 2 })
camera.x, camera.z = 12, 12
CRWeather.Update(0.6)
check(rec.systems["CR/LeafLitter/Live"] == "CR/LeafLitter" and rec.attached["CR/LeafLitter/Live"],
    "litter system follows the camera")
check((rec.rates["CR/LeafLitter/Live"] or 0) > 10, "dense foliage in a gale sheds leaves")
check(rec.forces["CR/LeafLitter/Live"] ~= nil and rec.forces["CR/LeafLitter/Live"]:match("^0%.000 %-0%.9 [1-9]"),
    "leaves are pushed downwind and fall: " .. tostring(rec.forces["CR/LeafLitter/Live"]))
camera.x, camera.z = 5000, 5000
CRWeather.Update(0.6)
check(rec.rates["CR/LeafLitter/Live"] == 0, "bare ground sheds nothing")
check(near(Foliage.LitterDensity(12, 12), 1.0) and Foliage.LitterDensity(5000, 5000) == 0, "density follows placements")

-- Save/load rebuilds the scene: litter is recreated, wind rewritten.
CRWeather.ResetSystems()
rec.systems = {}
CRWeather.SetPreset("FoliageTestGale", 0.05)
camera.x, camera.z = 12, 12
for _ = 1, 3 do CRWeather.Update(0.6) end
check(rec.systems["CR/LeafLitter/Live"] ~= nil, "litter is recreated after a scene rebuild")

-- Scale 0 holds still without unregistering.
Foliage.SetScale(0)
CRWeather.Update(0.001)
check(rec.colors["CR/GrassWind"].a == 0, "scale 0 stills the foliage")
Foliage.SetScale(1)

-- Teardown: every material still, the litter gone, nothing registered.
CRWeather.Shutdown()
for _, name in ipairs({ "CR17/LeavesWind", "CR/GrassWind" }) do
    local c = rec.colors[name]
    check(c.r == 0 and c.g == 0 and c.b == 0 and c.a == 0, name .. " is left still for the next mission")
end
check(rec.systems["CR/LeafLitter/Live"] == nil, "shutdown destroys the litter")
check(Foliage.Describe().materials == 0, "shutdown forgets the registrations")

-- Without exu's colour setter nothing fails.
exu.SetMaterialPassColors = nil
check(Foliage.Register("CR17/GroundWind") == true, "an EXU without SetMaterialPassColors degrades quietly")
Foliage.Update(0.1, CRWeather)
Foliage.Stop()

if failures > 0 then
    print(failures .. " foliage wind check(s) failed")
    os.exit(1)
end
print("FOLIAGE WIND OK")
