-- Lua 5.1 host regression: a snow world (Europa, from the TRN atlas) puts
-- surfaceSnow on every shared material, owned clones and the terrain atlas,
-- never on cockpit materials, and clears it on reset. Other worlds write none.
local E, objects, snowOf, stateOf = {}, {}, {}, {}
local atlas = "eu_detail_atlas"
local N = 40
for h = 1, N do objects[h] = { material = "mat" .. h, class = h == 2 and "turret" or "tank" } end
package.loaded.exu = E
package.loaded.CRWeather = { GetSurfaceWetness = function() return 0 end }
package.loaded.CRWorldArt = { Detect = function(trn)
    local stems = { eu = "europa", ma = "mars" }
    return stems[string.sub(trn.atlas, 1, 2)]
end }
function GetMapTRNFilename() return "misn12.trn" end
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
function E.SetMaterialShaderVector(name, key, a)
    -- Terrain has surfaceSnow but no surfaceState.
    if key == "surfaceState" then
        if name == "EU_DETAIL_ATLAS" then return 0 end
        stateOf[name] = a; return 1
    end
    if key == "surfaceSnow" then snowOf[name] = a; return 1 end
    return 0
end
function E.EntityLocalPoint(_, p) return p end
function E.GetWeaponMuzzlePosition() end
function E.IsGunTowerPowered() return true end
local view = 0
function E.GetCameraView() return view end
function E.GetSatState() return 0 end
function E.SetReactiveChunksEnabled() end
function E.GetEffectiveRenderProfile() return "Enhanced" end
function E.SetSurfaceFragmentProgram() return 1 end

local S = assert(loadfile("Scripts/CRSurfaceEffects.lua"))()
view = 1 -- cockpit view: its "panel" material must stay clear of snow
for h = 1, N do S.Register(h) end
for _ = 1, 200 do S.Update(0.05) end

assert(snowOf.EU_DETAIL_ATLAS and snowOf.EU_DETAIL_ATLAS > 0.5, "terrain atlas takes snow")
for h = 1, N do
    if h ~= 2 then assert(snowOf["mat" .. h] and snowOf["mat" .. h] > 0.5, "mat" .. h .. " has snow") end
end
local tower = objects[2].material
assert(tower ~= "mat2" and snowOf[tower] and snowOf[tower] > 0.5, "tower clone has snow")
assert(not snowOf.panel, "cockpit material never gets snow")
local cockpitClone = objects[1].cockpit
assert(cockpitClone and cockpitClone ~= "panel" and not snowOf[cockpitClone], "cockpit clone never gets snow")

S.ResetScene()
assert(snowOf.EU_DETAIL_ATLAS == 0 and snowOf.mat5 == 0, "reset clears snow")

-- A non-snow world writes nothing.
atlas = "ma_detail_atlas"
snowOf = {}
view = 0
for h = 1, N do objects[h].material = "mat" .. h; S.Register(h) end
for _ = 1, 200 do S.Update(0.05) end
assert(next(snowOf) == nil, "Mars gets no snow writes")

print("SurfaceSnow: Europa materials, clones, terrain atlas, cockpit excluded, reset, other worlds PASS")
