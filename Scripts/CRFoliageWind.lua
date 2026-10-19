-- CRFoliageWind.lua
-- Feeds CRWeather's wind to the foliage sway shaders and blows leaf litter.
--
-- CRWeather stays the only wind authority: this module keeps no wind of its
-- own. CRWeather.Update calls Update with itself once it has stepped, so a
-- mission only registers its wind materials and, if it wants leaves, the
-- places foliage stands.
--
-- Shader contract (cr17_wind.program, CR_grasswind.program): one float4 pass
-- colour carries the wind, xz = horizontal wind velocity in m/s (world), y =
-- gust 0..1, w = overall scale (0 holds the foliage still). The CR17 programs
-- read it from the pass emissive colour, CR_GrassWind from specular, because
-- the CR_Textured fragment program already reads emissive as lighting.
--
-- Ogre materials outlive the mission's Lua state, so a material left bent by
-- one mission would stay bent in the next. Register and Stop both write calm.
local CRFoliageWind = {
    Materials = {},   -- name -> { slot = "emissive" | "specular" }
    Order = {},
    Scale = 1.0,
    Sent = nil,       -- last wind written: { x, gust, z, scale }
    Litter = nil,     -- live leaf system state, see EnableLitter
    LitterSpec = nil,
    Sources = nil,    -- foliage density grid for litter
    Clock = 0.0,
}

local LITTER_SYSTEM = "CR/LeafLitter/Live"
local LITTER_TEMPLATE = "CR/LeafLitter"
local LITTER_PAYLOAD = "cr_foliage"
local CELL = 32.0

-- Optional like everywhere else in CR: an EXU without these entry points must
-- leave the foliage still, never abort the mission.
local okExu, exuModule = pcall(require, "exu")

local function Exu()
    local exu = okExu and exuModule or rawget(_G, "exu")
    return type(exu) == "table" and exu or nil
end

local function Call(name, ...)
    local exu = Exu()
    local fn = exu and exu[name]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

local function Clamp01(value)
    if value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

local function Finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function WriteMaterial(name, entry, x, gust, z, scale)
    -- Technique -1 / pass -1: every quality scheme, LOD and the glow pass. The
    -- glow fragment reads diffuse (CR17) or emissive (grass), never the slot
    -- carrying wind, so the bloom mask is untouched.
    return Call("SetMaterialPassColors", name, {
        [entry.slot] = { r = x, g = gust, b = z, a = scale },
    }, -1, -1, nil, true) == true
end

-- Registers a wind material: a material on a cr17_wind or CR_GrassWind vertex
-- program, drawn only on meshes baked by Tools/Bake-FoliageSway.py.
--   options.slot  "emissive" (CR17, the default) or "specular" (CR_GrassWind)
function CRFoliageWind.Register(material, options)
    if type(material) ~= "string" or material == "" then
        return false, "material name required"
    end
    options = type(options) == "table" and options or {}
    local slot = options.slot or "emissive"
    if slot ~= "emissive" and slot ~= "specular" then
        return false, "slot must be emissive or specular"
    end
    if CRFoliageWind.Materials[material] == nil then
        CRFoliageWind.Order[#CRFoliageWind.Order + 1] = material
    end
    local entry = { slot = slot }
    CRFoliageWind.Materials[material] = entry
    WriteMaterial(material, entry, 0.0, 0.0, 0.0, 0.0)
    CRFoliageWind.Sent = nil
    return true
end

function CRFoliageWind.SetScale(scale)
    CRFoliageWind.Scale = math.max(0.0, tonumber(scale) or 1.0)
    CRFoliageWind.Sent = nil
end

-- Leaf litter follows the camera and only falls where foliage stands. Points
-- are { x, y, z, ... } arrays (the CRJungle17Sites layout) or { x =, z = }
-- tables; they are binned into a 32 m grid once, so a few thousand
-- placements cost nothing per frame.
--   options.rate        leaves per second at full wind over dense foliage (40)
--   options.saturation  placements within ~48 m that count as dense (60)
--   options.minSpeed    wind below which nothing is shed, m/s (2.5)
function CRFoliageWind.EnableLitter(points, options)
    options = type(options) == "table" and options or {}
    local grid = {}
    for _, p in ipairs(points or {}) do
        local x = tonumber(p.x or p[1])
        local z = tonumber(p.z or p[3])
        if Finite(x) and Finite(z) then
            local key = math.floor(x / CELL) .. ":" .. math.floor(z / CELL)
            grid[key] = (grid[key] or 0) + 1
        end
    end
    CRFoliageWind.Sources = grid
    CRFoliageWind.LitterSpec = {
        rate = math.max(0.0, tonumber(options.rate) or 40.0),
        saturation = math.max(1.0, tonumber(options.saturation) or 60.0),
        minSpeed = math.max(0.0, tonumber(options.minSpeed) or 2.5),
    }
    return true
end

-- Foliage placements around a world position, 0 (bare) to 1 (dense).
function CRFoliageWind.LitterDensity(x, z)
    local grid = CRFoliageWind.Sources
    local spec = CRFoliageWind.LitterSpec
    if grid == nil or spec == nil then
        return 0.0
    end
    local cx, cz = math.floor(x / CELL), math.floor(z / CELL)
    local count = 0
    for dx = -1, 1 do
        for dz = -1, 1 do
            count = count + (grid[(cx + dx) .. ":" .. (cz + dz)] or 0)
        end
    end
    return Clamp01(count / spec.saturation)
end

local function CameraPosition()
    local matrix = Call("GetCameraTransformMatrix")
    if type(matrix) == "table" or type(matrix) == "userdata" then
        local ok, x, z = pcall(function()
            if matrix.posit_x ~= nil then return matrix.posit_x, matrix.posit_z end
            local p = matrix.posit or matrix.position
            if p ~= nil then return p.x, p.z end
        end)
        if ok and Finite(x) and Finite(z) then
            return x, z
        end
    end
    if type(GetPlayerHandle) == "function" and type(GetPosition) == "function" then
        local ok, p = pcall(function() return GetPosition(GetPlayerHandle()) end)
        if ok and p ~= nil and Finite(p.x) and Finite(p.z) then
            return p.x, p.z
        end
    end
    return nil
end

local function DestroyLitter()
    if CRFoliageWind.Litter ~= nil then
        Call("DetachParticleSystem", LITTER_SYSTEM)
        Call("DestroyParticleSystem", LITTER_SYSTEM)
    end
    CRFoliageWind.Litter = nil
end

local function CreateLitter()
    local templates = package.loaded["CRParticleTemplates"]
    if templates == nil then
        local ok, loaded = pcall(require, "CRParticleTemplates")
        templates = ok and loaded or nil
    end
    if templates == nil or not templates.EnsureExtra(LITTER_PAYLOAD) then
        CRFoliageWind.Litter = { failed = true }
        return
    end
    if Call("CreateParticleSystem", LITTER_SYSTEM, LITTER_TEMPLATE) ~= true then
        CRFoliageWind.Litter = { failed = true }
        return
    end
    Call("SetParticleSystemKeepLocalSpace", LITTER_SYSTEM, false)
    Call("SetParticleSystemNonVisibleUpdateTimeout", LITTER_SYSTEM, 2.0)
    if type(SetVector) == "function" then
        Call("AttachParticleSystemToCamera", LITTER_SYSTEM, SetVector(0, 0, 0))
    end
    CRFoliageWind.Litter = { rate = 0.0, density = 0.0, nextSample = 0.0, sent = {} }
end

local function Changed(sent, key, value, epsilon)
    local old = sent[key]
    if old ~= nil and math.abs(old - value) < epsilon then
        return false
    end
    sent[key] = value
    return true
end

local function UpdateLitter(dt, x, z, speed, gust)
    local spec = CRFoliageWind.LitterSpec
    if spec == nil then
        return
    end
    if CRFoliageWind.Litter == nil then
        CreateLitter()
    end
    local litter = CRFoliageWind.Litter
    if litter.failed then
        return
    end

    if CRFoliageWind.Clock >= litter.nextSample then
        litter.nextSample = CRFoliageWind.Clock + 0.5
        local cx, cz = CameraPosition()
        litter.density = cx and CRFoliageWind.LitterDensity(cx, cz) or 0.0
    end

    local windFactor = Clamp01((speed - spec.minSpeed) / 10.0) * (0.6 + 0.8 * gust)
    local rate = spec.rate * litter.density * windFactor * CRFoliageWind.Scale
    if Changed(litter.sent, "rate", rate, 0.5) then
        Call("SetParticleEmitterEmissionRate", LITTER_SYSTEM, 0, rate)
    end

    if speed < 0.01 then
        return
    end
    local dx, dz = x / speed, z / speed
    local turned = Changed(litter.sent, "dx", dx, 0.05)
    turned = Changed(litter.sent, "dz", dz, 0.05) or turned
    if turned then
        if type(SetVector) == "function" then
            Call("SetParticleEmitterDirection", LITTER_SYSTEM, 0, SetVector(dx, 0.15, dz))
        end
    end
    if Changed(litter.sent, "speed", speed, 0.5) then
        Call("SetParticleEmitterVelocity", LITTER_SYSTEM, 0, 0.3 * speed, 0.6 * speed)
        -- A leaf is a sail: the wind keeps pushing it while it falls.
        local push = 0.25 * speed * (1.0 + 0.5 * gust)
        Call("SetParticleAffectorParameter", LITTER_SYSTEM, 0, "force_vector",
            string.format("%.3f -0.9 %.3f", dx * push, dz * push))
    end
end

-- The horizontal wind CRWeather reports. Its GetWind vector includes the
-- preset's fall direction (precipitation leans, so y is usually -1), so the
-- bearing comes from xz alone and the magnitude from GetWindSpeed.
function CRFoliageWind.ReadWind(weather)
    if type(weather) ~= "table" or type(weather.GetWind) ~= "function" then
        return 0.0, 0.0, 0.0, 0.0
    end
    local ok, wind = pcall(weather.GetWind)
    if not ok or wind == nil or not Finite(wind.x) or not Finite(wind.z) then
        return 0.0, 0.0, 0.0, 0.0
    end
    local okSpeed, speed = pcall(weather.GetWindSpeed or function() return 0.0 end)
    speed = (okSpeed and Finite(speed)) and math.max(0.0, speed) or 0.0
    local horizontal = math.sqrt(wind.x * wind.x + wind.z * wind.z)
    if horizontal < 1e-4 or speed <= 0.0 then
        return 0.0, 0.0, 0.0, 0.0
    end
    local gust = 0.0
    if type(weather.GetGust) == "function" then
        local okGust, value = pcall(weather.GetGust)
        if okGust and Finite(value) then gust = Clamp01(value) end
    end
    return wind.x / horizontal * speed, wind.z / horizontal * speed, speed, gust
end

function CRFoliageWind.Update(dt, weather)
    dt = tonumber(dt) or 0.0
    CRFoliageWind.Clock = CRFoliageWind.Clock + dt
    weather = weather or package.loaded["CRWeather"]
    local x, z, speed, gust = CRFoliageWind.ReadWind(weather)
    local scale = CRFoliageWind.Scale

    -- Wind drifts slowly; rewriting dozens of passes every frame for a change
    -- nobody can see is wasted renderer work.
    local sent = CRFoliageWind.Sent
    if sent == nil or math.abs(sent[1] - x) > 0.05 or math.abs(sent[2] - gust) > 0.02
        or math.abs(sent[3] - z) > 0.05 or sent[4] ~= scale
    then
        for _, name in ipairs(CRFoliageWind.Order) do
            WriteMaterial(name, CRFoliageWind.Materials[name], x, gust, z, scale)
        end
        CRFoliageWind.Sent = { x, gust, z, scale }
    end

    UpdateLitter(dt, x, z, speed, gust)
end

-- Save/load rebuilds the scene: the litter system is gone, the materials are
-- not. Forget the litter so the next Update recreates it.
function CRFoliageWind.ResetScene()
    CRFoliageWind.Litter = nil
    CRFoliageWind.Sent = nil
end

function CRFoliageWind.Stop()
    for _, name in ipairs(CRFoliageWind.Order) do
        WriteMaterial(name, CRFoliageWind.Materials[name], 0.0, 0.0, 0.0, 0.0)
    end
    DestroyLitter()
    CRFoliageWind.Materials = {}
    CRFoliageWind.Order = {}
    CRFoliageWind.Sent = nil
    CRFoliageWind.LitterSpec = nil
    CRFoliageWind.Sources = nil
    CRFoliageWind.Scale = 1.0
    CRFoliageWind.Clock = 0.0
end

function CRFoliageWind.Describe()
    local litter = CRFoliageWind.Litter
    local sent = CRFoliageWind.Sent
    return {
        materials = #CRFoliageWind.Order,
        wind = sent and { x = sent[1], gust = sent[2], z = sent[3], scale = sent[4] } or nil,
        litter = litter == nil and "off" or (litter.failed and "failed" or "on"),
        litterRate = litter and litter.sent and litter.sent.rate or 0,
        litterDensity = litter and litter.density or 0,
    }
end

return CRFoliageWind
