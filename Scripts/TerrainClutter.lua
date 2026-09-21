-- TerrainClutter.lua
--
-- Campaign-owned, data-driven placement for mission-scoped clutter. Phase A
-- deliberately builds once through EXU/Ogre StaticGeometry and performs no
-- per-frame placement or per-instance animation work.

local TerrainClutter = {}

local okExu, exu = pcall(require, "exu")
if not okExu then
    exu = nil
end

local active = {}
local MODULUS = 2147483647
local MULTIPLIER = 48271

local function Log(message)
    print("[TerrainClutter] " .. tostring(message))
end

local function ReadClockSeconds()
    if type(os) == "table" and type(os.clock) == "function" then
        return os.clock()
    end
    return nil
end

local function IsFinite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function NewRandom(seed)
    local state = math.floor(math.abs(tonumber(seed) or 1)) % (MODULUS - 1) + 1
    return function()
        state = (state * MULTIPLIER) % MODULUS
        return state / MODULUS
    end
end

local function ResolvePosition(value)
    if type(value) == "table" and value.path then
        local ok, position = pcall(GetPosition, value.path, value.point or 0)
        if ok then return position end
        return nil
    end
    if type(value) == "string" then
        local ok, position = pcall(GetPosition, value, 0)
        if ok then return position end
        return nil
    end
    if value and IsFinite(value.x) and IsFinite(value.y) and IsFinite(value.z) then
        return value
    end
    return nil
end

local function IsExcluded(profile, position)
    for i = 1, #(profile.exclusionAreas or {}) do
        if type(IsInsideArea) == "function" then
            local ok, inside = pcall(IsInsideArea, profile.exclusionAreas[i], position)
            if ok and inside then return true end
        end
    end

    for i = 1, #(profile.exclusionCircles or {}) do
        local exclusion = profile.exclusionCircles[i]
        local center = ResolvePosition(exclusion.center or exclusion)
        local radius = tonumber(exclusion.radius) or 0.0
        if center and radius > 0.0 then
            local dx = position.x - center.x
            local dz = position.z - center.z
            if dx * dx + dz * dz < radius * radius then return true end
        end
    end

    return false
end

local function NormalizeTerrainTypes(terrainTypes)
    if terrainTypes == nil then return nil end
    if type(terrainTypes) ~= "table" then return false end
    local wanted = {}
    for i = 1, #terrainTypes do
        wanted[terrainTypes[i]] = true
    end
    return wanted
end

local function ValidateProfile(profile)
    if type(profile) ~= "table" then return nil, "profile is absent or not a table" end
    if type(profile.name) ~= "string" or profile.name == "" then return nil, "name is required" end
    if type(profile.mesh) ~= "string" or profile.mesh == "" then return nil, "mesh is required" end
    if type(profile.material) ~= "string" or profile.material == "" then return nil, "material is required" end
    if not ResolvePosition(profile.center) then return nil, "center could not be resolved" end
    if not IsFinite(profile.radius) or profile.radius <= 0.0 then return nil, "radius must be positive" end
    if not IsFinite(profile.density) or profile.density <= 0.0 then return nil, "density must be positive" end
    if not IsFinite(profile.minScale) or not IsFinite(profile.maxScale) or
       profile.minScale <= 0.0 or profile.maxScale < profile.minScale then
        return nil, "scale range is invalid"
    end

    local terrainTypes = NormalizeTerrainTypes(profile.terrainTypes)
    if terrainTypes == false then return nil, "terrainTypes must be an array" end
    if terrainTypes and type(profile.terrainTypeAt) ~= "function" then
        return nil, "terrainTypes requires a terrainTypeAt(position) capability"
    end

    return {
        center = ResolvePosition(profile.center),
        terrainTypes = terrainTypes,
    }
end

local function SampleTerrain(position)
    if type(GetTerrainHeightAndNormal) ~= "function" then return nil end
    local ok, height, normal = pcall(GetTerrainHeightAndNormal, position)
    if not ok or not IsFinite(height) or normal == nil or not IsFinite(normal.y) then return nil end
    return height, normal
end

local function GetSlopeDegrees(normal)
    local up = math.max(-1.0, math.min(1.0, normal.y))
    return math.acos(up) * 180.0 / math.pi
end

function TerrainClutter.BuildLayer(profile)
    local validated, validationError = ValidateProfile(profile)
    if not validated then
        Log("skipped: " .. validationError)
        return false, validationError
    end
    if not (exu and type(exu.CreateStaticGeometry) == "function") then
        local message = "EXU StaticGeometry API is unavailable"
        Log("skipped " .. profile.name .. ": " .. message)
        return false, message
    end

    local startedAt = ReadClockSeconds()

    TerrainClutter.DestroyLayer(profile.name)

    local random = NewRandom(profile.seed or 1)
    local area = math.pi * profile.radius * profile.radius
    local targetCount = math.max(1, math.floor(area * profile.density + 0.5))
    targetCount = math.min(targetCount, profile.maxInstances or 100000)
    local maxAttempts = math.max(targetCount, math.floor(targetCount * (profile.maxAttemptFactor or 8)))
    local slopeMin = profile.slopeMin or 0.0
    local slopeMax = profile.slopeMax or 90.0
    local heightMin = profile.heightMin or -math.huge
    local heightMax = profile.heightMax or math.huge
    local instances = {}
    local attempts = 0

    while #instances < targetCount and attempts < maxAttempts do
        attempts = attempts + 1
        local radius = profile.radius * math.sqrt(random())
        local angle = random() * math.pi * 2.0
        local x = validated.center.x + math.cos(angle) * radius
        local z = validated.center.z + math.sin(angle) * radius
        local query = SetVector(x, validated.center.y, z)
        local height, normal = SampleTerrain(query)

        if height then
            local position = SetVector(x, height + (profile.baseOffset or 0.02), z)
            local slope = GetSlopeDegrees(normal)
            local terrainAccepted = true
            if validated.terrainTypes then
                local ok, terrainType = pcall(profile.terrainTypeAt, position)
                terrainAccepted = ok and validated.terrainTypes[terrainType] == true
            end

            local aboveWater = profile.waterLevel == nil or height > profile.waterLevel
            if slope >= slopeMin and slope <= slopeMax and
               height >= heightMin and height <= heightMax and
               aboveWater and terrainAccepted and not IsExcluded(profile, position) then
                local scale = profile.minScale + (profile.maxScale - profile.minScale) * random()
                instances[#instances + 1] = {
                    position = position,
                    yaw = random() * math.pi * 2.0,
                    scale = scale,
                }
            end
        end
    end

    if #instances == 0 then
        local message = "no valid terrain samples"
        Log("skipped " .. profile.name .. ": " .. message)
        return false, message
    end

    local info, createError = exu.CreateStaticGeometry(
        profile.name,
        profile.mesh,
        profile.material,
        instances,
        {
            regionDimensions = profile.regionDimensions or { x = 128.0, y = 256.0, z = 128.0 },
            origin = profile.origin or validated.center,
            renderingDistance = profile.renderingDistance or 0.0,
            castShadows = profile.castShadows == true,
            visible = profile.visible ~= false,
        })
    if not info then
        Log("build failed " .. profile.name .. ": " .. tostring(createError))
        return false, createError
    end

    info.seed = profile.seed or 1
    info.attemptCount = attempts
    info.targetCount = targetCount
    local finishedAt = ReadClockSeconds()
    info.startupMilliseconds = startedAt and finishedAt and
        math.floor((finishedAt - startedAt) * 1000.0 + 0.5) or
        (info.buildMilliseconds or 0)
    active[profile.name] = info
    Log(string.format(
        "built %s: instances=%d target=%d attempts=%d regions=%d buildMs=%s startupMs=%s",
        profile.name,
        info.instanceCount or #instances,
        targetCount,
        attempts,
        info.regionCount or 0,
        tostring(info.buildMilliseconds or "?"),
        tostring(info.startupMilliseconds or "?")))
    return true, info
end

function TerrainClutter.DestroyLayer(name)
    if type(name) ~= "string" then return false end
    local existed = active[name] ~= nil
    local destroyed = false
    if exu and type(exu.DestroyStaticGeometry) == "function" then
        destroyed = exu.DestroyStaticGeometry(name) == true
    end
    active[name] = nil
    if existed or destroyed then Log("destroyed " .. name) end
    return destroyed or existed
end

function TerrainClutter.Shutdown()
    local count = 0
    if exu and type(exu.DestroyAllStaticGeometry) == "function" then
        count = exu.DestroyAllStaticGeometry() or 0
    end
    active = {}
    Log("shutdown: cleared=" .. tostring(count))
    return count
end

function TerrainClutter.GetLayerInfo(name)
    return active[name]
end

-- Wind animation is deferred, but all future foliage wind reads must come
-- through CRWeather.GetWind(). This safe read creates no parallel wind state.
function TerrainClutter.GetWind()
    local weather = rawget(_G, "CRWeather")
    if type(weather) == "table" and type(weather.GetWind) == "function" then
        local ok, wind = pcall(weather.GetWind)
        if ok and wind and IsFinite(wind.x) and IsFinite(wind.y) and IsFinite(wind.z) then
            return wind
        end
    end
    return SetVector(0.0, 0.0, 0.0)
end

return TerrainClutter
