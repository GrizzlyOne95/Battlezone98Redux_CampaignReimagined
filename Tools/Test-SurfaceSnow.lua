-- Lua 5.1 host regression: a snow world (Europa, from the TRN atlas) puts
-- surfaceSnow on every shared material, owned clones and the terrain atlas,
-- never on cockpit materials, and clears it on reset. Other worlds write none.
-- A dust world (Mars) puts surfaceDust on the same objects, never on cockpit
-- materials, and on terrain only when the map has a baked shape mask
-- (surfaceTerrain, from CRTerrainShape).
local E, objects, snowOf, stateOf, iceOf, dustOf, shapeOf, cameraOf, washOf = {}, {}, {}, {}, {}, {}, {}, {}, {}
local atlas, map = "eu_detail_atlas", "misn12"
local N = 40
for h = 1, N do
    objects[h] = { material = "mat" .. h, class = h == 2 and "turret" or h == 4 and "person" or "tank",
        pos = { x = 100 + h * 20, y = h == 5 and 90 or 42, z = 97500 } }
end
function GetPosition(h) return objects[h] and objects[h].pos end
function GetTerrainHeightAndNormal() return 40 end
package.loaded.exu = E
package.loaded.CRWeather = { GetSurfaceWetness = function() return 0 end }
package.loaded.CRWorldArt = { Detect = function(trn)
    local stems = { eu = "europa", ma = "mars" }
    return stems[string.sub(trn.atlas, 1, 2)]
end }
package.loaded.CRTerrainShape = {
    misn12 = { "EU_DETAIL_ATLAS", 1e-4, 2e-4, 0, -19 },
    misn06 = { "MA_DETAIL_ATLAS", 1e-4, 2e-4, 0.5, -19.25 },
    misn04 = { "EU_DETAIL_ATLAS", 1e-4, 2e-4, 0, -19.25 }, -- wrong atlas: ignored
}
function GetMapTRNFilename() return "Missions\\" .. map .. ".trn" end
function OpenODF() return { atlas = atlas } end
function GetODFString(trn, section, key, default)
    if section == "Atlases" and key == "MaterialName" then return trn.atlas, true end
    return default, false
end
function IsValid(h) return objects[h] ~= nil end
function GetPlayerHandle() return 1 end
function IsCraft() return true end
function GetClassLabel(h) return objects[h].class end
function GetHealth() return 1 end
function GetDistance() return 10 end
function SetVector(x, y, z) return { x = x, y = y, z = z } end
local function obj(t) return objects[type(t) == "table" and t.handle or t] end
function E.GetSubEntityCount() return 1 end
function E.GetSubEntityMaterial(t) return type(t) == "table" and (obj(t).cockpit or "panel") or obj(t).material end
function E.SetSubEntityMaterial(t, _, name) if type(t) == "table" then obj(t).cockpit = name else obj(t).material = name end return true end
E.SetSurfaceMaterial = E.SetSubEntityMaterial
function E.CloneSurfaceMaterial() return true end
function E.ReleaseSurfaceMaterial() return true end
function E.SetMaterialShaderVector(name, key, a, b, c, d)
    -- Terrain has surfaceSnow but no surfaceState.
    if key == "surfaceState" then
        if name == "EU_DETAIL_ATLAS" then return 0 end
        stateOf[name] = a; return 1
    end
    if key == "surfaceSnow" then snowOf[name] = a; iceOf[name] = d; return 1 end
    if key == "surfaceDust" then
        if name == "EU_DETAIL_ATLAS" then return 0 end
        dustOf[name] = d; return 1
    end
    if key == "surfaceTerrain" then shapeOf[name] = { a, b, c, d }; return 1 end
    if key == "surfaceCamera" then cameraOf[name] = { a, b, c }; return 1 end
    if string.sub(key, 1, 11) == "surfaceWash" then washOf[name .. ":" .. string.sub(key, 12)] = { a, b, c, d }; return 1 end
    return 0
end
function E.EntityLocalPoint(_, p) return p end
function E.GetWeaponMuzzlePosition() end
function E.IsGunTowerPowered() return true end
local view = 0
function E.GetCameraView() return view end
local camera = { posit_x = 100, posit_y = 40, posit_z = 97500 }
function E.GetCameraTransformMatrix() return camera end
function E.GetSatState() return 0 end
function E.SetReactiveChunksEnabled() end
function E.GetEffectiveRenderProfile() return "Enhanced" end
function E.SetSurfaceFragmentProgram() return 1 end

local S = assert(loadfile("Scripts/CRSurfaceEffects.lua"))()
view = 1 -- cockpit view: its "panel" material must stay clear of snow
for h = 1, N do S.Register(h) end
for _ = 1, 200 do S.Update(0.05) end

assert(snowOf.EU_DETAIL_ATLAS and snowOf.EU_DETAIL_ATLAS > 0.1 and snowOf.EU_DETAIL_ATLAS < 0.2, "terrain atlas takes its own lighter snow cover")
assert(iceOf.EU_DETAIL_ATLAS and iceOf.EU_DETAIL_ATLAS > 0.5, "terrain atlas takes ice depth")
assert(shapeOf.EU_DETAIL_ATLAS and shapeOf.EU_DETAIL_ATLAS[1] == 1e-4 and shapeOf.EU_DETAIL_ATLAS[4] == -19,
    "terrain atlas takes the map's shape transform")
for name in pairs(shapeOf) do assert(name == "EU_DETAIL_ATLAS", name .. " is not terrain") end
assert(cameraOf.EU_DETAIL_ATLAS and cameraOf.EU_DETAIL_ATLAS[3] == 97500, "shaped terrain takes the camera position")
camera.posit_x = 180; S.Update(0.05)
assert(cameraOf.EU_DETAIL_ATLAS[1] == 180, "camera position follows the camera")
for name in pairs(cameraOf) do assert(name == "EU_DETAIL_ATLAS", name .. " is not terrain") end
-- Thruster wash: the nearest low-hovering craft, never a person or a high craft.
local washed = {}
for slot = 0, 5 do
    local w = washOf["EU_DETAIL_ATLAS:" .. slot]
    assert(w and w[4] > 0.9 and w[3] == 8, "wash slot " .. slot .. " is a hovering craft")
    washed[w[1]] = true
end
assert(not washed[180] and not washed[200], "people and high craft never wash")
for key in pairs(washOf) do assert(string.sub(key, 1, 16) == "EU_DETAIL_ATLAS:", key .. " is not terrain") end
for h = 1, N do
    if h ~= 2 then assert(snowOf["mat" .. h] and snowOf["mat" .. h] > 0.2, "mat" .. h .. " has snow") end
end
local tower = objects[2].material
assert(tower ~= "mat2" and snowOf[tower] and snowOf[tower] > 0.2, "tower clone has snow")
assert(not snowOf.panel, "cockpit material never gets snow")
local cockpitClone = objects[1].cockpit
assert(cockpitClone and cockpitClone ~= "panel" and not snowOf[cockpitClone], "cockpit clone never gets snow")

S.ResetScene()
assert(snowOf.EU_DETAIL_ATLAS == 0 and snowOf.mat5 == 0, "reset clears snow")
assert(next(dustOf) == nil, "Europa gets no dust writes")
assert(shapeOf.EU_DETAIL_ATLAS[1] == 0, "reset clears the shape transform")
for slot = 0, 5 do assert(washOf["EU_DETAIL_ATLAS:" .. slot][4] == 0, "reset clears wash slot " .. slot) end

-- A non-snow world writes nothing.
atlas, map = "ma_detail_atlas", "misn06"
snowOf, shapeOf = {}, {}
view = 0
for h = 1, N do objects[h].material = "mat" .. h; S.Register(h) end
for _ = 1, 200 do S.Update(0.05) end
assert(next(snowOf) == nil, "Mars gets no snow writes")
for h = 1, N do
    local m = objects[h].material
    assert(dustOf[m] and dustOf[m] > 0.2, m .. " has dust")
end
assert(not dustOf.panel, "cockpit material never gets dust")
assert(dustOf.MA_DETAIL_ATLAS and dustOf.MA_DETAIL_ATLAS > 0.2, "shaped Mars terrain takes dust")
assert(shapeOf.MA_DETAIL_ATLAS and shapeOf.MA_DETAIL_ATLAS[3] == 0.5, "Mars terrain takes its shape tile")
S.ResetScene()
assert(dustOf.mat5 == 0 and dustOf.MA_DETAIL_ATLAS == 0, "reset clears dust")

-- A map without a shape entry (or with another atlas's entry) keeps its
-- terrain free of dust and shape writes.
map, dustOf, shapeOf = "misn04", {}, {}
for h = 1, N do objects[h].material = "mat" .. h; S.Register(h) end
for _ = 1, 200 do S.Update(0.05) end
assert(dustOf.mat5 and not dustOf.MA_DETAIL_ATLAS, "unshaped terrain gets no dust")
assert(next(shapeOf) == nil, "atlas mismatch writes no shape")
cameraOf, washOf = {}, {}; S.Update(0.05); camera.posit_x = 300; S.Update(0.05)
-- Rain puddles still need the camera on unshaped terrain; wash stays off.
assert(cameraOf.MA_DETAIL_ATLAS and next(washOf) == nil, "unshaped terrain takes camera but no wash writes")
S.ResetScene()

print("SurfaceSnow: Europa materials, clones, terrain atlas, cockpit excluded, reset, other worlds, Mars dust, terrain shape PASS")
