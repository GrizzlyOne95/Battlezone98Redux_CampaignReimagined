-- Test-TerrainClutter.lua
-- Host test for deterministic placement, lifecycle, filtering, and safe wind.

local scripts = arg[1] or "Scripts"
package.path = scripts .. "/?.lua;" .. package.path

local createCalls = {}
local events = {}
local destroyAllCalls = 0

local exu = {}

function exu.CreateStaticGeometry(name, mesh, material, instances, options)
    events[#events + 1] = "create:" .. name
    createCalls[#createCalls + 1] = {
        name = name,
        mesh = mesh,
        material = material,
        instances = instances,
        options = options,
    }
    return {
        name = name,
        instanceCount = #instances,
        regionCount = math.max(1, math.ceil(#instances / 32)),
        buildMilliseconds = 0,
    }
end

function exu.DestroyStaticGeometry(name)
    events[#events + 1] = "destroy:" .. name
    return true
end

function exu.DestroyAllStaticGeometry()
    destroyAllCalls = destroyAllCalls + 1
    events[#events + 1] = "destroy-all"
    return #createCalls
end

package.preload.exu = function() return exu end

function SetVector(x, y, z)
    return { x = x, y = y, z = z }
end

function GetPosition(path, point)
    assert(path == "test_path")
    assert(point == 0)
    return SetVector(0, 10, 0)
end

function GetTerrainHeightAndNormal(position)
    return 10 + position.x * 0.01, SetVector(0, 1, 0)
end

function IsInsideArea(name, position)
    return name == "never_used" and position.x == 99999
end

local function Assert(condition, message)
    if not condition then error(message or "assertion failed", 2) end
end

local function AssertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function AssertInstancesEqual(left, right)
    AssertEqual(#left, #right, "deterministic instance count")
    for i = 1, #left do
        local a, b = left[i], right[i]
        AssertEqual(a.position.x, b.position.x, "position x at " .. i)
        AssertEqual(a.position.y, b.position.y, "position y at " .. i)
        AssertEqual(a.position.z, b.position.z, "position z at " .. i)
        AssertEqual(a.yaw, b.yaw, "yaw at " .. i)
        AssertEqual(a.scale, b.scale, "scale at " .. i)
    end
end

local TerrainClutter = require("TerrainClutter")

local profile = {
    name = "TestGrass",
    mesh = "crgrass.mesh",
    material = "CR/GrassPrototype",
    center = { path = "test_path", point = 0 },
    radius = 20,
    density = 0.2,
    maxInstances = 40,
    minScale = 0.7,
    maxScale = 1.2,
    slopeMin = 0,
    slopeMax = 15,
    heightMin = 0,
    heightMax = 100,
    waterLevel = 0,
    seed = 418,
    exclusionCircles = {
        { center = SetVector(0, 10, 0), radius = 4 },
    },
}

-- BZR's Lua sandbox does not expose the standard os library. Exercise that
-- runtime shape explicitly so optional timing can never block placement.
local savedOs = os
os = nil
local ok, firstInfo = TerrainClutter.BuildLayer(profile)
os = savedOs
Assert(ok, "first build must succeed")
AssertEqual(firstInfo.instanceCount, 40, "first instance count")
Assert(type(firstInfo.startupMilliseconds) == "number", "startup timing must be reported")
AssertEqual(firstInfo.startupMilliseconds, firstInfo.buildMilliseconds,
    "sandbox timing falls back to native build time")
local firstInstances = createCalls[1].instances
for i = 1, #firstInstances do
    local p = firstInstances[i].position
    Assert(p.x * p.x + p.z * p.z >= 16, "exclusion circle rejected instance " .. i)
end

ok = TerrainClutter.BuildLayer(profile)
Assert(ok, "rebuild must succeed")
AssertInstancesEqual(firstInstances, createCalls[2].instances)
AssertEqual(events[3], "destroy:TestGrass", "rebuild destroys the active layer first")
AssertEqual(events[4], "create:TestGrass", "rebuild creates once after destroy")

local invalidOk = TerrainClutter.BuildLayer(nil)
Assert(invalidOk == false, "absent profile must fail gracefully")

local terrainTypeProfile = {}
for key, value in pairs(profile) do terrainTypeProfile[key] = value end
terrainTypeProfile.name = "TerrainTypeWithoutQuery"
terrainTypeProfile.terrainTypes = { 1 }
invalidOk = TerrainClutter.BuildLayer(terrainTypeProfile)
Assert(invalidOk == false, "terrain type filter without query must fail gracefully")

local savedCreate = exu.CreateStaticGeometry
exu.CreateStaticGeometry = nil
invalidOk = TerrainClutter.BuildLayer(profile)
Assert(invalidOk == false, "missing native API must fail gracefully")
exu.CreateStaticGeometry = savedCreate

CRWeather = nil
local wind = TerrainClutter.GetWind()
AssertEqual(wind.x, 0, "absent weather wind x")
AssertEqual(wind.y, 0, "absent weather wind y")
AssertEqual(wind.z, 0, "absent weather wind z")

CRWeather = { GetWind = function() return SetVector(0, 0, 0) end }
wind = TerrainClutter.GetWind()
AssertEqual(wind.x, 0, "zero wind x")
AssertEqual(wind.y, 0, "zero wind y")
AssertEqual(wind.z, 0, "zero wind z")

for _, count in ipairs({ 32, 128, 512 }) do
    local stress = {}
    for key, value in pairs(profile) do stress[key] = value end
    stress.name = "Stress" .. count
    stress.radius = 45
    stress.density = 1
    stress.maxInstances = count
    stress.exclusionCircles = nil
    ok, firstInfo = TerrainClutter.BuildLayer(stress)
    Assert(ok, "stress build must succeed at " .. count)
    AssertEqual(firstInfo.instanceCount, count, "stress instance count " .. count)
end

local cleared = TerrainClutter.Shutdown()
Assert(cleared > 0, "shutdown reports cleared native objects")
AssertEqual(destroyAllCalls, 1, "shutdown calls native cleanup exactly once")
Assert(TerrainClutter.GetLayerInfo(profile.name) == nil, "shutdown clears Lua layer state")

print(string.format(
    "TerrainClutter tests passed: deterministic=%d stress=%s cleanup=%d",
    #firstInstances,
    "32/128/512",
    cleared))
