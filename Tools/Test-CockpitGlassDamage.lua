-- Lua 5.1 host regression: cockpit glass cracks by hull stage (with
-- hysteresis, fixed spot, edge-triggered CRWetGlass calls) and a brief eased
-- electrical brownout on real hull loss.
local E, uniforms = {}, {}
local health, view, player = 1, 1, 1
local crackCalls, updates, glassAlpha, glassWant = {}, 0, 0, 0
local Glass = {}
function Glass.SetCrack(level, x, y) crackCalls[#crackCalls + 1] = { level = level, x = x, y = y }; glassWant = level end
function Glass.Update() updates = updates + 1
    if glassAlpha < glassWant then glassAlpha = math.min(glassWant, glassAlpha + 0.1)
    else glassAlpha = math.max(glassWant, glassAlpha - 0.1) end
end
function Glass.Busy() return glassWant > 0 or glassAlpha > 0 end
package.loaded.CRWetGlass = Glass
package.loaded.exu = E
package.loaded.CRWeather = { GetSurfaceWetness = function() return 0 end }
function IsValid(h) return h == 1 or h == 7 end
function GetPlayerHandle() return player end
function IsCraft() return true end
function GetClassLabel() return "wingman" end
function GetHealth() return health end
function GetDistance() return 10 end
function SetVector(x, y, z) return { x = x, y = y, z = z } end
local cockpitMaterial = "panel"
function E.GetSubEntityCount() return 1 end
function E.GetSubEntityMaterial(t) return type(t) == "table" and cockpitMaterial or "metal" end
function E.SetSubEntityMaterial(t, _, name) if type(t) == "table" then cockpitMaterial = name end return true end
E.SetSurfaceMaterial = E.SetSubEntityMaterial
function E.CloneSurfaceMaterial() return true end
function E.ReleaseSurfaceMaterial() return true end
function E.SetSurfaceTexture() return 1 end
function E.SetMaterialShaderVector(name, key, ...) uniforms[name .. key] = { ... }; return 1 end
function E.EntityLocalPoint(_, p) return p end
function E.GetWeaponMuzzlePosition() end
function E.IsGunTowerPowered() return true end
function E.GetCameraView() return view end
function E.GetSatState() return 0 end
function E.SetReactiveChunksEnabled() end
local profile = "Enhanced"
function E.GetEffectiveRenderProfile() return profile end
function E.SetSurfaceFragmentProgram() return 1 end

local S = assert(loadfile("Scripts/CRSurfaceEffects.lua"))()
S.Register(1)
local function ticks(n) for _ = 1, n do S.Update(0.05) end end
local function brown() local v = uniforms[cockpitMaterial .. "surfaceState"]; return v and v[4] or 0 end
local function lastCrack() return crackCalls[#crackCalls] end
ticks(20)
assert(cockpitMaterial:find("_cockpit"), "cockpit runs on an owned clone")

-- 1. Healthy: no glass work at all.
assert(#crackCalls == 0 and updates == 0, "healthy hull leaves the glass alone")
assert(brown() == 0, "no brownout when healthy")

-- 2. Hull 45%: a faint crack, once, and the glass is driven every frame.
health = 0.45; ticks(4)
assert(#crackCalls == 1 and lastCrack().level == 0.35, "faint crack below 50%")
local spot = { x = lastCrack().x, y = lastCrack().y }
assert(spot.x >= 0.3 and spot.x <= 0.7 and math.abs(spot.x - 0.5) >= 0.08 - 1e-9, "crack keeps off the reticle")
assert(spot.y >= 0.26 and spot.y <= 0.44, "crack sits in the glass band")
local u = updates; ticks(10)
assert(updates - u >= 10 and #crackCalls == 1, "edge-triggered SetCrack, Update every frame")

-- 3. Hysteresis: 52% keeps the crack; 56% clears it, Update runs until faded.
health = 0.52; ticks(10)
assert(#crackCalls == 1, "no chatter inside the hysteresis band")
health = 0.56; ticks(2)
assert(lastCrack().level == 0, "repair above 55% clears the crack")
ticks(20)
u = updates; ticks(10)
assert(updates == u, "glass is no longer driven once the crack faded")

-- 4. Below 25%: the strong crack at the same spot; 28% holds it.
health = 0.2; ticks(4)
assert(lastCrack().level == 0.8 and lastCrack().x == spot.x and lastCrack().y == spot.y, "strong crack, same spot")
local n = #crackCalls
health = 0.28; ticks(10)
assert(#crackCalls == n, "strong crack holds until 30%")
health = 0.4; ticks(2)
assert(lastCrack().level == 0.35, "partial repair drops back to the faint crack")

-- 5. Leaving the cockpit view clears it; returning restores it at the same spot.
view = 2; ticks(4)
assert(lastCrack().level == 0, "leaving F1 clears the crack")
view = 1; ticks(20)
assert(lastCrack().level == 0.35 and lastCrack().x == spot.x, "returning to F1 restores the same crack")

-- 6. Brownout: a real 10% hull loss dims the cockpit briefly and smoothly.
health = 0.9; ticks(60)
assert(lastCrack().level == 0, "repaired craft has clear glass")
assert(brown() == 0, "no brownout from repair")
health = 0.8
local peak, maxStep, last = 0, 0, 0
for i = 1, 60 do
    ticks(1)
    local b = brown(); maxStep = math.max(maxStep, math.abs(b - last)); last = b
    peak = math.max(peak, b)
end
assert(peak > 0.2 and peak <= 0.6, "brownout depth, got " .. peak)
assert(maxStep < 0.3, "brownout eases, max step " .. maxStep)
assert(brown() < 0.01, "brownout recovers within three seconds, got " .. brown())

-- 7. Small chip damage and repair never brown out.
health = 0.79; ticks(10); health = 0.78; ticks(10)
assert(brown() == 0, "small hull chips do not brown out")

-- 8. A new craft rebases the hull sample (no brownout on boarding).
player = 7; health = 0.6; ticks(20)
assert(brown() == 0, "boarding a damaged craft does not brown out")

-- 9. Disabling mid-crack clears it and keeps fading it out.
player = 1; health = 0.4; ticks(20)
assert(lastCrack().level == 0.35, "crack before disabling")
S.SetEnabled(false)
assert(lastCrack().level == 0, "disabling clears the crack")
u = updates; for _ = 1, 10 do S.Update(0.05) end
assert(updates > u, "a cleared crack still fades while disabled")
for _ = 1, 20 do S.Update(0.05) end
u = updates; for _ = 1, 5 do S.Update(0.05) end
assert(updates == u, "glass work stops once faded")
S.SetEnabled(true); S.Register(1)

-- 10. Leaving Enhanced clears the crack too.
health = 0.4; ticks(20)
assert(lastCrack().level == 0.35, "crack back after re-enabling")
profile = "Stock"; ticks(2)
assert(lastCrack().level == 0, "leaving Enhanced clears the crack")
profile = "Enhanced"

-- 11. Crack spots are bounded: two craft with a one-entry cache.
S.MaxCrackSpots = 1
player = 7; health = 0.4; ticks(20)
player = 1; ticks(20)
assert(S.crackSpotCount <= 1, "spot cache bounded, got " .. S.crackSpotCount)
assert(lastCrack().x == spot.x, "an evicted spot comes back the same (it is a hash)")

-- 12. Without CRWetGlass nothing fails.
package.loaded.CRWetGlass = nil
local S2 = assert(loadfile("Scripts/CRSurfaceEffects.lua"))()
health = 0.2; S2.Register(1)
for _ = 1, 20 do S2.Update(0.05) end
assert(S2.crackLevel == 0, "no glass module, no crack state")

print("CockpitGlassDamage: stages, hysteresis, spot, view, brownout, chips, boarding, disable, Enhanced gate, no module PASS")
