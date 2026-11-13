-- Lua 5.1 host regression: rain wetness reaches every shared material and
-- owned clone in small, synchronised steps (no per-material pops or lag).
local E, objects, wetOf, calls = {}, {}, {}, 0
local rain = 0
local N = 300
for h = 1, N do objects[h] = { material = "mat" .. h, class = h == 2 and "turret" or "tank" } end
package.loaded.exu = E
package.loaded.CRWeather = { GetSurfaceWetness = function() return rain end }
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
function E.SetSurfaceTexture() return 1 end
function E.SetMaterialShaderVector(name, key, a)
    calls = calls + 1
    if key == "surfaceState" then wetOf[name] = a end
    return 1
end
function E.EntityLocalPoint(_, p) return p end
function E.GetWeaponMuzzlePosition() end
function E.IsGunTowerPowered() return true end
function E.GetCameraView() return 0 end
function E.GetSatState() return 0 end
function E.SetReactiveChunksEnabled() end
function E.GetEffectiveRenderProfile() return "Enhanced" end
function E.SetSurfaceFragmentProgram() return 1 end

local S = assert(loadfile("Scripts/CRSurfaceEffects.lua"))()
for h = 1, N do S.Register(h) end
for _ = 1, 200 do S.Update(0.05) end
assert(#S.materialOrder >= N, "all shared materials discovered, got " .. #S.materialOrder)
local tower = objects[2].material
assert(tower ~= "mat2", "tower runs on an owned clone")

local EPS = 1e-6
local function names()
    local list = {}
    for _, name in ipairs(S.materialOrder) do if name ~= "mat2" then list[#list + 1] = name end end
    list[#list + 1] = tower
    return list
end
local tracked = names()

-- Drive the weather and check, every tick, that each material moved at most
-- MaxWetStep and that no two materials are more than one step apart.
local function run(target, seconds)
    rain = target
    local last, maxStep, maxSpread, maxCalls = {}, 0, 0, 0
    for _, n in ipairs(tracked) do last[n] = wetOf[n] or 0 end
    for _ = 1, math.floor(seconds / 0.05) do
        calls = 0
        S.Update(0.05)
        maxCalls = math.max(maxCalls, calls)
        local lo, hi = math.huge, -math.huge
        for _, n in ipairs(tracked) do
            local v = wetOf[n] or 0
            maxStep = math.max(maxStep, math.abs(v - last[n])); last[n] = v
            lo, hi = math.min(lo, v), math.max(hi, v)
        end
        maxSpread = math.max(maxSpread, hi - lo)
    end
    return last, maxStep, maxSpread, maxCalls
end

local final, step, spread, perTick = run(1, 30)
assert(step <= S.MaxWetStep + EPS, "wetting step too large: " .. step)
assert(spread <= S.MaxWetStep + 0.001 + EPS, "materials drift apart while wetting: " .. spread)
for _, n in ipairs(tracked) do assert(final[n] > 0.95, n .. " never got wet: " .. final[n]) end
assert(final[tower] > 0.95, "tower clone follows the rain")
assert(perTick <= S.MaxMaterialBudget + S.CloneWetBudget + 40, "per-tick work is bounded: " .. perTick)

-- Steady rain: back to the small idle budget, no rewrites.
calls = 0
for _ = 1, 40 do S.Update(0.05) end
assert(calls < 40 * 4, "steady rain does not rewrite materials: " .. calls)

final, step, spread = run(0, 60)
assert(step <= S.MaxWetStep + EPS, "drying step too large: " .. step)
assert(spread <= S.MaxWetStep + 0.001 + EPS, "materials drift apart while drying: " .. spread)
for _, n in ipairs(tracked) do assert(final[n] < 0.05, n .. " never dried: " .. final[n]) end

-- Scene reset clears the sweep.
S.ResetScene()
assert(S.SweepWet == 0 and S.sweepLeft == 0 and S.cloneLeft == 0, "reset clears the sweep")

print("SurfaceWetSweep: " .. N .. " materials + tower clone, bounded steps, synchronised, wet/dry, idle, reset PASS")
